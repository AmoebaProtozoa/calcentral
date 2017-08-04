module MyAcademics
  class CollegeAndLevel
    include AcademicsModule
    include ClassLogger
    include DatedFeed

    CS_DATE_FORMAT = "%Y-%m-%d"

    def merge(data)
      college_and_level = hub_college_and_level

      # If we have no profile at all, consider the no-profile to be active for the current term.
      if college_and_level[:empty]
        college_and_level[:termName] = Berkeley::Terms.fetch.current.to_english
        college_and_level[:isCurrent] = true
      else
        # The key name is a bit misleading, since the profile might be for a future term.
        college_and_level[:isCurrent] = !profile_in_past?(college_and_level)
      end
      data[:collegeAndLevel] = college_and_level
    end

    def hub_college_and_level
      # academic_status is a pointer to an obj in memory and should not be modified, other functions may need to use it later
      academic_status = get_academic_status.clone
      if (holds = parse_hub_holds academic_status)
        academic_status[:holds] = holds
      end
      academic_status[:awardHonors] = parse_hub_award_honors academic_status
      academic_status[:roles] = parse_hub_roles academic_status

      if (statuses = parse_hub_academic_statuses academic_status)
        status = statuses.first
        registration_term = status['currentRegistration'].try(:[], 'term')
        academic_status[:careers] = parse_hub_careers statuses
        academic_status[:level] = parse_hub_level statuses
        academic_status[:termName] = parse_hub_term_name(registration_term).try(:[], 'name')
        academic_status[:termId] = registration_term.try(:[], 'id')
        academic_status[:termsInAttendance] = status['termsInAttendance'].to_s
        academic_status.merge! parse_hub_plans statuses
      else
        academic_status[:empty] = true
      end
      if (degrees = parse_hub_degrees academic_status)
        academic_status[:degrees] = degrees
      end
      academic_status.delete(:feed)
      academic_status
    end

    def parse_hub_holds(response)
      holds = {hasHolds: false}
      holds_feed = response[:feed] && response[:feed]['student'] && response[:feed]['student']['holds']
      if holds_feed.present?
        holds[:hasHolds] = true if holds_feed.to_a.length > 0
      end
      holds
    end

    def parse_hub_award_honors(response)
      honors = sort_award_honors response.try(:[], :feed).try(:[], 'student').try(:[], 'awardHonors')
      honors_by_term = {}
      honors.try(:each) do |honor|
        term_id = honor.try(:[], 'term').try(:[], 'id')
        honors_by_term[term_id] ||= []
        honors_by_term[term_id] << {
          awardDate: parse_date(honor.try(:[], 'awardDate')),
          code: honor.try(:[], 'type').try(:[], 'code'),
          description: honor.try(:[], 'type').try(:[], 'description')
        }
      end
      honors_by_term
    end

    def sort_award_honors(honors)
      honors.try(:sort_by) do |honor|
        honor.try(:[], 'term').try(:[], 'id')
      end.try(:reverse)
    end

    def parse_date(date)
      pretty_date = ''
      begin
        pretty_date = format_date(strptime_in_time_zone(date, CS_DATE_FORMAT), '%b %d, %Y')[:dateString] unless date.blank?
      rescue => e
        logger.error "Error parsing date: #{date} for uid = #{@uid}; caused by: #{e}"
      end
      pretty_date
    end

    def parse_hub_roles(response)
      response.try(:[], :feed).try(:[], 'student').try(:[], 'roles')
    end

    def parse_hub_level(statuses)
      level = statuses.collect do |status|
        status['currentRegistration'].try(:[], 'academicLevel').try(:[], 'level').try(:[], 'description')
      end.uniq.reject { |level| level.to_s.empty? }.to_sentence
      level.blank? ? nil : level
    end

    def parse_hub_plans(statuses)
      plan_set = {
        majors: [],
        minors: [],
        designatedEmphases: [],
        plans: [],
        lastExpectedGraduationTerm: { code: nil, name: nil }
      }

      filtered_statuses = filter_inactive_status_plans(statuses)

      filtered_statuses.each do |status|
        Array.wrap(status.try(:[], 'studentPlans')).each do |plan|
          flattened_plan = flatten_plan(plan)
          plan_set[:plans] << flattened_plan

          group_plans_by_type(plan_set, flattened_plan)

          # Catch Last Expected Graduation Date
          if (plan_set[:lastExpectedGraduationTerm].try(:[], :code).to_i < flattened_plan[:expectedGraduationTerm].try(:[], :code).to_i)
            plan_set[:lastExpectedGraduationTerm] = flattened_plan[:expectedGraduationTerm]
          end
        end
      end
      plan_set
    end

    def parse_hub_degrees(response)
      if (degrees = response.try(:[], :feed).try(:[], 'student').try(:[], 'degrees'))
        awarded_degrees = degrees.select do |degree|
          status = degree.try(:[], 'status').try(:[], 'code')
          status === 'Awarded'
        end
        awarded_degrees unless awarded_degrees.empty?
      end
    end

    def group_plans_by_type(plan_set, plan)
      college_plan = {college: plan[:college]}
      case plan[:type].try(:[], :category)
        when 'Major'
          plan_set[:majors] << college_plan.merge({
            major: plan[:plan].try(:[], :description),
            subPlan: plan[:subPlan].try(:[], :description)
          })
        when 'Minor'
          plan_set[:minors] << college_plan.merge({
            minor: plan[:plan].try(:[], :description),
            subPlan: plan[:subPlan].try(:[], :description)
          })
        when 'Designated Emphasis'
          plan_set[:designatedEmphases] << college_plan.merge({
            designatedEmphasis: plan[:plan].try(:[], :description),
            subPlan: plan[:subPlan].try(:[], :description)
          })
      end
    end

    def filter_inactive_status_plans(statuses)
      statuses.each do |status|
        status['studentPlans'].select! do |plan|
          plan.try(:[], 'statusInPlan').try(:[], 'status').try(:[], 'code') == 'AC'
        end
      end
      statuses
    end

    def parse_hub_term_name(term)
      if term
        term['name'] = Berkeley::TermCodes.normalized_english term.try(:[], 'name')
      end
      term
    end

    def get_academic_status
      @academic_status ||= HubEdos::MyAcademicStatus.new(@uid).get_feed
    end

    def flatten_plan(hub_plan)
      flat_plan = {
        career: {},
        program: {},
        plan: {},
        subPlan: {}
      }
      if (academic_plan = hub_plan['academicPlan'])
        # Get CPP
        academic_program = academic_plan.try(:[], 'academicProgram')
        career = academic_program.try(:[], 'academicCareer')
        program = academic_program.try(:[], 'program')
        plan = academic_plan.try(:[], 'plan')

        # Extract CPP
        flat_plan[:career].merge!({
          code: career.try(:[], 'code'),
          description: career.try(:[], 'description')
        })
        flat_plan[:program].merge!({
          code: program.try(:[], 'code'),
          description: program.try(:[], 'description')
        })
        flat_plan[:plan].merge!({
          code: plan.try(:[], 'code'),
          description: plan.try(:[], 'description')
        })

        if (academic_sub_plan = hub_plan['academicSubPlan'])
          sub_plan = academic_sub_plan.try(:[], 'subPlan')
          flat_plan[:subPlan].merge!({
            code: sub_plan.try(:[], 'code'),
            description: sub_plan.try(:[], 'description')
          })
        end

        if (hub_plan['expectedGraduationTerm'])
          expected_grad_term_name = hub_plan['expectedGraduationTerm'].try(:[], 'name')
          flat_plan[:expectedGraduationTerm] = {
            code: hub_plan['expectedGraduationTerm'].try(:[], 'id'),
            name: Berkeley::TermCodes.normalized_english(expected_grad_term_name)
          }
        end
        flat_plan[:role] = hub_plan[:role]
        flat_plan[:enrollmentRole] = hub_plan[:enrollmentRole]
        flat_plan[:primary] = !!hub_plan['primary']
        flat_plan[:type] = categorize_plan_type(academic_plan['type'])

        # TODO: Need to re-evaluate the proper field for college name. See adminOwners
        flat_plan[:college] = academic_plan['academicProgram'].try(:[], 'program').try(:[], 'description')
      end
      flat_plan
    end

    def categorize_plan_type(type)
      case type.try(:[], 'code')
        when 'MAJ', 'SS', 'SP', 'HS', 'CRT'
          category = 'Major'
        when 'MIN'
          category = 'Minor'
        when 'DE'
          category = 'Designated Emphasis'
      end
      {
        code: type['code'],
        description: type['description'],
        category: category
      }
    end

    def profile_in_past?(profile)
      if !profile[:empty] && (term = Berkeley::TermCodes.from_english profile[:termName])
        time_bucket(term[:term_yr], term[:term_cd]) == 'past'
      else
        false
      end
    end
  end
end
