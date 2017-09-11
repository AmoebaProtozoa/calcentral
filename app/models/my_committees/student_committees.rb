module MyCommittees
  class StudentCommittees

    include CommitteesModule
    include ClassLogger

    def merge(feed)
      feed.merge! get_feed
    end

    def get_feed
      result = {
        studentCommittees: []
      }
      feed = CampusSolutions::StudentCommittees.new(user_id: @uid).get[:feed]

      if feed && (cs_committees = feed[:ucSrStudentCommittee][:studentCommittees])
        result[:studentCommittees] = parse_cs_student_committees cs_committees
      end
      result
    end

    def parse_cs_student_committees (cs_committees)
      cs_committees.compact!
      committees_result = []
      cs_committees.try(:each) do |cs_committee|
        committees_result << parse_student_cs_committee(cs_committee)
      end
      committees_result.compact
    end

    def parse_student_cs_committee(cs_committee)
      remove_inactive_members(cs_committee) if (is_active = is_active?(cs_committee))
      committee = parse_cs_committee(cs_committee)
      committee[:isActive] = is_active
      committee
    end

    def parse_cs_milestone_attempts(cs_committee)
      attempts = cs_committee[:studentApprovalMilestoneAttempts].try(:map) do |attempt|
        parse_cs_milestone_attempt(attempt)
      end
      return [] unless attempts
      attempts.try(:sort_by) do |attempt|
        attempt[:sequenceNumber]
      end.last(1)
    end

    def format_milestone_attempt(milestone_attempt)
      if first_attempt_exam_passed?(milestone_attempt)
        "#{milestone_attempt[:result]} #{milestone_attempt[:date]}"
      else
        "Exam #{milestone_attempt[:sequenceNumber]}: #{milestone_attempt[:result]} #{milestone_attempt[:date]}"
      end
    end

    def first_attempt_exam_passed?(milestone_attempt)
      milestone_attempt[:sequenceNumber] === 1 && milestone_attempt[:result] == Berkeley::GraduateMilestones::QE_RESULTS_STATUS_PASSED
    end

    def parse_cs_committee_member (cs_committee_member)
      {
        name: "#{cs_committee_member[:memberNameFirst]} #{cs_committee_member[:memberNameLast]}",
        email: cs_committee_member[:memberEmail],
        photo: committee_member_photo_url(cs_committee_member),
        primaryDepartment:  cs_committee_member[:memberDeptDescr],
        serviceRange: format_member_service_dates(cs_committee_member)
      }
    end

    def remove_inactive_members(cs_committee)
      cs_committee[:committeeMembers].try(:reject!) do |member|
        inactive?(member)
      end
    end

    def inactive?(committee_member)
      inactive = false
      begin
        inactive = Time.zone.parse(committee_member[:memberEndDate].to_s).to_datetime.try(:past?)
      rescue
        logger.error "Bad Format for committee member end date; Class #{self.class.name} feed, uid = #{@uid}"
      end
      inactive
    end

  end
end
