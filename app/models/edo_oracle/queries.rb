module EdoOracle
  class Queries < Connection
    include ActiveRecordHelper
    include ClassLogger

    ABSENTIA_CODE = 'OGPFABSENT'.freeze
    FILING_FEE_CODE = 'BGNNFILING'.freeze

    CANONICAL_SECTION_ORDERING = 'section_display_name, primary DESC, instruction_format, section_num'

    # Changes from CampusOracle::Queries section columns:
    #   - 'course_cntl_num' now 'section_id'
    #   - 'term_yr' and 'term_cd' replaced by 'term_id'
    #   - 'catalog_suffix_1' and 'catalog_suffix_2' replaced by 'catalog_suffix' (combined)
    #   - 'primary_secondary_cd' replaced by Boolean 'primary'
    #   - 'course_display_name' and 'section_display_name' added
    SECTION_COLUMNS = <<-SQL
      sec."id" AS section_id,
      sec."term-id" AS term_id,
      sec."session-id" AS session_id,
      TRIM(crs."title") AS course_title,
      TRIM(crs."transcriptTitle") AS course_title_short,
      crs."subjectArea" AS dept_name,
      crs."classSubjectArea" AS dept_code,
      sec."primary" AS primary,
      sec."sectionNumber" AS section_num,
      sec."component-code" as instruction_format,
      sec."primaryAssociatedSectionId" as primary_associated_section_id,
      sec."displayName" AS section_display_name,
      xlat."courseDisplayName" AS course_display_name,
      crs."catalogNumber-formatted" AS catalog_id,
      crs."catalogNumber-number" AS catalog_root,
      crs."catalogNumber-prefix" AS catalog_prefix,
      crs."catalogNumber-suffix" AS catalog_suffix
    SQL

    JOIN_SECTION_TO_COURSE = <<-SQL
      LEFT OUTER JOIN SISEDO.DISPLAYNAMEXLATV01_MVW xlat ON (
        xlat."classDisplayName" = sec."displayName")
      LEFT OUTER JOIN SISEDO.API_COURSEV01_MVW crs ON (
        xlat."courseDisplayName" = crs."displayName")
    SQL

    JOIN_ROSTER_TO_EMAIL = <<-SQL
       LEFT OUTER JOIN SISEDO.PERSON_EMAILV00_VW email ON (
         email."PERSON_KEY" = enroll."STUDENT_ID" AND
         email."EMAIL_PRIMARY" = 'Y')
    SQL

    def self.where_course_term_updated_date(with_career_filter = true)
      enroll_acad_career_filter = with_career_filter ? 'AND term2.ACAD_CAREER = enr."ACAD_CAREER"' : ''
      sql_clause = <<-SQL
        AND crs."updatedDate" = (
          SELECT MAX(crs2."updatedDate")
          FROM SISEDO.API_COURSEV01_MVW crs2, SISEDO.EXTENDED_TERM_MVW term2
          WHERE crs2."cms-version-independent-id" = crs."cms-version-independent-id"
          AND crs2."displayName" = crs."displayName"
          #{enroll_acad_career_filter}
          AND term2.STRM = sec."term-id"
          AND (
            (
              CAST(crs2."fromDate" AS DATE) <= term2.TERM_BEGIN_DT
              AND CAST(crs2."toDate" AS DATE) >= term2.TERM_END_DT
            )
            OR CAST(crs."updatedDate" AS DATE) = TO_DATE('1901-01-01', 'YYYY-MM-DD')
          )
        )
      SQL
      sql_clause
    end

    # EDO equivalent of CampusOracle::Queries.get_enrolled_sections
    # Changes:
    #   - 'wait_list_seq_num' replaced by 'waitlist_position'
    #   - 'course_option' removed
    #   - 'cred_cd' and 'pnp_flag' replaced by 'grading_basis'
    def self.get_enrolled_sections(person_id, terms = nil)
      # The push_pred hint below alerts Oracle to use indexes on SISEDO.API_COURSEV00_VW, aka crs.
      # Reduce performance hit and only add Terms whare clause if limiting number of terms pulled
      in_term_where_clause = "enr.\"TERM_ID\" IN (#{terms_query_list terms}) AND " if Settings.features.hub_term_api
      safe_query <<-SQL
        SELECT DISTINCT
          #{SECTION_COLUMNS},
          sec."maxEnroll" AS enroll_limit,
          enr."STDNT_ENRL_STATUS_CODE" AS enroll_status,
          enr."WAITLISTPOSITION" AS waitlist_position,
          enr."UNITS_TAKEN" AS units,
          enr."GRADE_MARK" AS grade,
          enr."GRADE_POINTS" AS grade_points,
          enr."GRADING_BASIS_CODE" AS grading_basis
        FROM SISEDO.CC_ENROLLMENTV00_VW enr
        JOIN SISEDO.CLASSSECTIONALLV00_MVW sec ON (
          enr."TERM_ID" = sec."term-id" AND
          enr."SESSION_ID" = sec."session-id" AND
          enr."CLASS_SECTION_ID" = sec."id" AND
          sec."status-code" IN ('A','S') )
        #{JOIN_SECTION_TO_COURSE}
        WHERE  #{in_term_where_clause}
          enr."CAMPUS_UID" = '#{person_id}'
          AND enr."STDNT_ENRL_STATUS_CODE" != 'D'
          #{where_course_term_updated_date}
        ORDER BY term_id DESC, #{CANONICAL_SECTION_ORDERING}
      SQL
    end

    # EDO equivalent of CampusOracle::Queries.get_instructing_sections
    # Changes:
    #   - 'cs-course-id' added.
    def self.get_instructing_sections(person_id, terms = nil)
      # Reduce performance hit and only add Terms whare clause if limiting number of terms pulled
      in_term_where_clause = " AND instr.\"term-id\" IN (#{terms_query_list terms})" if Settings.features.hub_term_api
      safe_query <<-SQL
        SELECT
          #{SECTION_COLUMNS},
          sec."cs-course-id" AS cs_course_id,
          sec."maxEnroll" AS enroll_limit,
          sec."maxWaitlist" AS waitlist_limit,
          sec."startDate" AS start_date,
          sec."endDate" AS end_date
        FROM SISEDO.ASSIGNEDINSTRUCTORV00_VW instr
        JOIN SISEDO.CLASSSECTIONALLV00_MVW sec ON (
          instr."term-id" = sec."term-id" AND
          instr."session-id" = sec."session-id" AND
          instr."cs-course-id" = sec."cs-course-id" AND
          instr."offeringNumber" = sec."offeringNumber" AND
          instr."number" = sec."sectionNumber")
        #{JOIN_SECTION_TO_COURSE}
        WHERE sec."status-code" IN ('A','S')
          #{in_term_where_clause}
          AND instr."campus-uid" = '#{person_id}'
          #{where_course_term_updated_date(false)}
        ORDER BY term_id DESC, #{CANONICAL_SECTION_ORDERING}
      SQL
    end

    # EDO equivalent of CampusOracle::Queries.get_secondary_sections.
    # Changes:
    #   - More precise associations allow us to query by primary section rather
    #     than course catalog ID.
    #   - 'cs-course-id' added.
    def self.get_associated_secondary_sections(term_id, section_id)
      safe_query <<-SQL
        SELECT DISTINCT
          #{SECTION_COLUMNS},
          sec."cs-course-id" AS cs_course_id,
          sec."maxEnroll" AS enroll_limit,
          sec."maxWaitlist" AS waitlist_limit
        FROM SISEDO.CLASSSECTIONALLV00_MVW sec
        #{JOIN_SECTION_TO_COURSE}
        WHERE sec."status-code" IN ('A','S')
          AND sec."primary" = 'false'
          AND sec."term-id" = '#{term_id}'
          AND sec."primaryAssociatedSectionId" = '#{section_id}'
          #{where_course_term_updated_date(false)}
        ORDER BY #{CANONICAL_SECTION_ORDERING}
      SQL
    end

    # EDO equivalent of CampusOracle::Queries.get_section_schedules
    # Changes:
    #   - 'course_cntl_num' is replaced with 'section_id'
    #   - 'term_yr' and 'term_cd' replaced by 'term_id'
    #   - 'session_id' added
    #   - 'building_name' and 'room_number' combined as 'location'
    #   - 'meeting_start_time_ampm_flag' is included in 'meeting_start_time' timestamp
    #   - 'meeting_end_time_ampm_flag' is included in 'meeting_end_time' timestamp
    #   - 'multi_entry_cd' obsolete now that multiple meetings directly associated with section
    #   - 'print_cd' replaced with 'print_in_schedule_of_classes' boolean
    #   - 'meeting_start_date' and 'meeting_end_date' added
    def self.get_section_meetings(term_id, section_id)
      safe_query <<-SQL
        SELECT DISTINCT
          sec."id" AS section_id,
          sec."printInScheduleOfClasses" AS print_in_schedule_of_classes,
          mtg."term-id" AS term_id,
          mtg."session-id" AS session_id,
          mtg."location-descr" AS location,
          mtg."meetsDays" AS meeting_days,
          mtg."startTime" AS meeting_start_time,
          mtg."endTime" AS meeting_end_time,
          mtg."startDate" AS meeting_start_date,
          mtg."endDate" AS meeting_end_date
        FROM
          SISEDO.MEETINGV00_VW mtg
        JOIN SISEDO.CLASSSECTIONALLV00_MVW sec ON (
          mtg."cs-course-id" = sec."cs-course-id" AND
          mtg."term-id" = sec."term-id" AND
          mtg."session-id" = sec."session-id" AND
          mtg."offeringNumber" = sec."offeringNumber" AND
          mtg."sectionNumber" = sec."sectionNumber"
        )
        WHERE
          sec."term-id" = '#{term_id}' AND
          sec."id" = '#{section_id}'
        ORDER BY meeting_start_date, meeting_start_time
      SQL
    end

    # No Campus Oracle equivalent.
    def self.get_section_final_exam(term_id, section_id)
      safe_query <<-SQL
        SELECT DISTINCT
          sec."term-id" AS term_id,
          sec."session-id" AS session_id,
          sec."id" AS section_id,
          sec."finalExam" AS exam_type,
          exam."date" AS exam_date,
          exam."startTime" AS exam_start_time,
          exam."endTime" AS exam_end_time,
          exam."location-descr" AS location
        FROM
          SISEDO.EXAMV00_VW exam
        RIGHT JOIN SISEDO.CLASSSECTIONALLV00_MVW sec ON (
          exam."cs-course-id" = sec."cs-course-id" AND
          exam."term-id" = sec."term-id" AND
          exam."session-id" = sec."session-id" AND
          exam."offeringNumber" = sec."offeringNumber" AND
          exam."sectionNumber" = sec."sectionNumber" AND
          exam."type-code" = 'FIN'
        )
        WHERE
          sec."term-id" = '#{term_id}' AND
          sec."id" = '#{section_id}' AND
          sec."finalExam" IN ('A', 'Y')
        ORDER BY exam_date
      SQL
    end

    # EDO equivalent of CampusOracle::Queries.get_sections_from_ccns
    # Changes:
    #   - 'course_cntl_num' is replaced with 'section_id'
    #   - 'term_yr' and 'term_cd' replaced by 'term_id'
    #   - 'catalog_suffix_1' and 'catalog_suffix_2' replaced by 'catalog_suffix' (combined)
    #   - 'primary_secondary_cd' replaced by Boolean 'primary'
    def self.get_sections_by_ids(term_id, section_ids)
      safe_query <<-SQL
        SELECT DISTINCT
          #{SECTION_COLUMNS}
        FROM SISEDO.CLASSSECTIONALLV00_MVW sec
        #{JOIN_SECTION_TO_COURSE}
        WHERE sec."term-id" = '#{term_id}'
          AND sec."id" IN (#{section_ids.collect { |id| id.to_i }.join(', ')})
          #{where_course_term_updated_date(false)}
        ORDER BY #{CANONICAL_SECTION_ORDERING}
      SQL
    end

    # EDO equivalent of CampusOracle::Queries.get_section_instructors
    # Changes:
    #   - 'ccn' replaced by 'section_id' argument
    #   - 'term_yr' and 'term_cd' replaced by 'term_id'
    #   - 'instructor_func' has become represented by 'role_code' and 'role_description'
    #   - Does not provide all user profile fields ('email_address', 'student_id', 'affiliations').
    #     This will require a programmatic join at a higher level.
    #     See CLC-6239 for implementation of batch LDAP profile requests.
    def self.get_section_instructors(term_id, section_id)
      safe_query <<-SQL
        SELECT DISTINCT
          TRIM(instr."formattedName") AS person_name,
          TRIM(instr."givenName") AS first_name,
          TRIM(instr."familyName") AS last_name,
          instr."campus-uid" AS ldap_uid,
          instr."role-code" AS role_code,
          instr."role-descr" AS role_description,
          instr."gradeRosterAccess" AS grade_roster_access,
          instr."printInScheduleOfClasses" AS print_in_schedule
        FROM
          SISEDO.ASSIGNEDINSTRUCTORV00_VW instr
        JOIN SISEDO.CLASSSECTIONALLV00_MVW sec ON (
          instr."cs-course-id" = sec."cs-course-id" AND
          instr."term-id" = sec."term-id" AND
          instr."session-id" = sec."session-id" AND
          instr."offeringNumber" = sec."offeringNumber" AND
          instr."number" = sec."sectionNumber"
        )
        WHERE
          sec."id" = '#{section_id.to_s}' AND
          sec."term-id" = '#{term_id.to_s}' AND
          TRIM(instr."instructor-id") IS NOT NULL
        ORDER BY
          role_code
      SQL
    end

    # EDO equivalent of CampusOracle::Queries.terms
    # Changes:
    #   - 'term_yr' and 'term_cd' replaced by 'term_id'
    #   - 'term_status', 'term_status_desc', and 'current_tb_term_flag' are not present.
    #     No indication of past, current, or future term status
    #   - Multiple entries for each term due to differing start and end dates that
    #     may exist for LAW as compared to GRAD, UGRAD, or UCBX
    def self.terms
      safe_query <<-SQL
        SELECT
          term."STRM" as term_code,
          trim(term."DESCR") AS term_name,
          term."TERM_BEGIN_DT" AS term_start_date,
          term."TERM_END_DT" AS term_end_date
        FROM
          SISEDO.TERM_TBL_VW term
        ORDER BY
          term_start_date desc
      SQL
    end

    # TODO: Update this and dependencies to require term
    def self.get_cross_listed_course_title(course_code)
      result = safe_query <<-SQL
        SELECT
          TRIM(crs."title") AS course_title,
          TRIM(crs."transcriptTitle") AS course_title_short
        FROM SISEDO.API_COURSEV01_MVW crs
        WHERE crs."updatedDate" = (
          SELECT MAX(CRS2."updatedDate") FROM SISEDO.API_COURSEV01_MVW crs2
          WHERE crs2."cms-version-independent-id" = crs."cms-version-independent-id"
          AND crs2."displayName" = crs."displayName"
        )
        AND crs."displayName" = '#{course_code}'
      SQL
      result.first if result
    end

    def self.get_subject_areas
      safe_query <<-SQL
        SELECT DISTINCT "subjectArea" FROM SISEDO.API_COURSEIDENTIFIERSV00_VW
      SQL
    end

    # EDO equivalent of CampusOracle::Queries.get_enrolled_students
    # Changes:
    #   - 'ccn' replaced by 'section_id' argument
    #   - 'pnp_flag' replaced by 'grading_basis'
    #   - 'term_yr' and 'term_yr' replaced by 'term_id'
    #   - 'calcentral_student_info_vw' data (first_name, last_name, student_email_address,
    #     affiliations) are not present as these are provided by the CalNet LDAP or HubEdos module.
    def self.get_enrolled_students(section_id, term_id)
      safe_query <<-SQL
        SELECT DISTINCT
          enroll."CAMPUS_UID" AS ldap_uid,
          enroll."STUDENT_ID" AS student_id,
          enroll."STDNT_ENRL_STATUS_CODE" AS enroll_status,
          enroll."WAITLISTPOSITION" AS waitlist_position,
          enroll."UNITS_TAKEN" AS units,
          TRIM(enroll."GRADING_BASIS_CODE") AS grading_basis
        FROM SISEDO.ENROLLMENTV00_VW enroll
        WHERE
          enroll."CLASS_SECTION_ID" = '#{section_id}'
          AND enroll."TERM_ID" = '#{term_id}'
          AND enroll."STDNT_ENRL_STATUS_CODE" != 'D'
      SQL
    end

    # Extended version of #get_enrolled_students used for rosters
    def self.get_rosters(ccns, term_id)
      if Settings.features.allow_alt_email_addr_for_enrollments
        join_roster_to_email = JOIN_ROSTER_TO_EMAIL
        email_col = ", email.\"EMAIL_EMAILADDRESS\" AS email_address"
      end

      safe_query <<-SQL
        SELECT DISTINCT
          enroll."CLASS_SECTION_ID" AS section_id,
          enroll."CAMPUS_UID" AS ldap_uid,
          enroll."STUDENT_ID" AS student_id,
          enroll."STDNT_ENRL_STATUS_CODE" AS enroll_status,
          enroll."WAITLISTPOSITION" AS waitlist_position,
          enroll."UNITS_TAKEN" AS units,
          enroll."ACAD_CAREER" AS academic_career,
          TRIM(enroll."GRADING_BASIS_CODE") AS grading_basis,
          plan."ACADPLAN_DESCR" AS major,
          plan."STATUSINPLAN_STATUS_CODE",
          stdgroup."HIGHEST_STDNT_GROUP" AS terms_in_attendance_group
          #{email_col}
        FROM SISEDO.ENROLLMENTV00_VW enroll
        LEFT OUTER JOIN
          SISEDO.STUDENT_PLAN_CC_V00_VW plan ON enroll."STUDENT_ID" = plan."STUDENT_ID" AND
          plan."ACADPLAN_TYPE_CODE" IN ('CRT', 'HS', 'MAJ', 'SP', 'SS')
        LEFT OUTER JOIN
          (
            SELECT s."STUDENT_ID", Max(s."STDNT_GROUP") AS "HIGHEST_STDNT_GROUP" FROM SISEDO.STUDENT_GROUPV00_VW s
            WHERE s."STDNT_GROUP" IN ('R1TA', 'R2TA', 'R3TA', 'R4TA', 'R5TA', 'R6TA', 'R7TA', 'R8TA')
            GROUP BY s."STUDENT_ID"
          ) stdgroup
          ON enroll."STUDENT_ID" = stdgroup."STUDENT_ID"
        #{join_roster_to_email}
        WHERE
          enroll."CLASS_SECTION_ID" IN ('#{ccns.join "','"}')
          AND enroll."TERM_ID" = '#{term_id}'
          AND enroll."STDNT_ENRL_STATUS_CODE" != 'D'
      SQL
    end

    # EDO equivalent of CampusOracle::Queries.has_instructor_history?
    def self.has_instructor_history?(ldap_uid, instructor_terms = nil)
      if instructor_terms.to_a.any?
        instructor_term_clause = "AND instr.\"term-id\" IN (#{terms_query_list instructor_terms.to_a})"
      end
      result = safe_query <<-SQL
        SELECT
          count(instr."term-id") AS course_count
        FROM
          SISEDO.ASSIGNEDINSTRUCTORV00_VW instr
        WHERE
          instr."campus-uid" = '#{ldap_uid}' AND
          rownum < 2
          #{instructor_term_clause}
      SQL
      if (result_row = result.first)
        Rails.logger.debug "Instructor #{ldap_uid} history for terms #{instructor_terms} count = #{result_row}"
        result_row['course_count'].to_i > 0
      else
        false
      end
    end

    def self.has_student_history?(ldap_uid, student_terms = nil)
      if student_terms.to_a.any?
        student_term_clause = "AND enroll.\"TERM_ID\" IN (#{terms_query_list student_terms.to_a})"
      end
      result = safe_query <<-SQL
        SELECT
          count(enroll."TERM_ID") AS enroll_count
        FROM
          SISEDO.CC_ENROLLMENTV00_VW enroll
        WHERE
          enroll."CAMPUS_UID" = '#{ldap_uid.to_i}' AND
          rownum < 2
          #{student_term_clause}
      SQL
      if (result_row = result.first)
        Rails.logger.debug "Student #{ldap_uid} history for terms #{student_terms} count = #{result_row}"
        result_row['enroll_count'].to_i > 0
      else
        false
      end
    end

    # Used to create mapping between Legacy CCNs and CS Section IDs.
    def self.get_section_id(term_id, department, catalog_id, instruction_format, section_num)
      compressed_dept = SubjectAreas.compress department
      uglified_course_name = "#{compressed_dept} #{catalog_id}"
      rows = safe_query <<-SQL
        SELECT
          sec."id" AS section_id
        FROM
          SISEDO.CLASSSECTIONALLV00_MVW sec
        WHERE
          sec."term-id" = '#{term_id}' AND
          sec."component-code" = '#{instruction_format}' AND
          sec."displayName" = '#{uglified_course_name}' AND
          sec."sectionNumber" = '#{section_num}'
      SQL
      if (row = rows.first)
        row['section_id']
      end
    end

    def self.get_registration_status (person_id)
      safe_query <<-SQL
        SELECT STUDENT_ID as student_id,
          ACADCAREER_CODE as acadcareer_code,
          TERM_ID as term_id,
          WITHCNCL_TYPE_CODE as withcncl_type_code,
          WITHCNCL_TYPE_DESCR as withcncl_type_descr,
          WITHCNCL_REASON_CODE as withcncl_reason_code,
          WITHCNCL_REASON_DESCR as withcncl_reason_descr,
          WITHCNCL_FROMDATE as withcncl_fromdate,
          WITHCNCL_LASTATTENDDATE as withcncl_lastattendate,
          SPLSTUDYPROG_TYPE_CODE as splstudyprog_type_code,
          SPLSTUDYPROG_TYPE_DESCR as splstudyprog_type_descr
        FROM
          SISEDO.STUDENT_REGISTRATIONV00_VW
        WHERE
          STUDENT_ID = '#{person_id}' AND
          (WITHCNCL_TYPE_CODE IS NOT NULL
            OR SPLSTUDYPROG_TYPE_CODE = '#{ABSENTIA_CODE}'
            OR SPLSTUDYPROG_TYPE_CODE = '#{FILING_FEE_CODE}')
      SQL
    end

  end
end
