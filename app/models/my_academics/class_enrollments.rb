module MyAcademics
  class ClassEnrollments < UserSpecificModel
    include SafeJsonParser
    include Cache::CachedFeed
    include Cache::UserCacheExpiry
    include CampusSolutions::EnrollmentCardFeatureFlagged

    def get_feed_internal
      return {} unless is_feature_enabled && user_is_student?
      HashConverter.camelize({
        enrollmentTermInstructionTypes: get_career_term_roles,
        enrollmentTermInstructions: get_enrollment_term_instructions,
        enrollmentTermAcademicPlanner: get_enrollment_term_academic_planner,
        hasHolds: user_has_holds?,
        links: get_links
      })
    end

    # Groups student plans into groups based on roles (e.g. 'default', 'fpf', 'concurrent')
    def grouped_student_plan_roles
      grouped_roles = {}
      active_plans.each do |plan|
        role_code = plan[:role]
        career_code = plan[:career][:code]
        role_key = [role_code, career_code]
        grouped_roles[role_key] = { role: role_code, career_code: career_code, academic_plans: [] } if grouped_roles[role_key].blank?
        grouped_roles[role_key][:academic_plans] << plan
      end
      grouped_roles
    end

    # Returns unique couplings of current career-terms and current student plan roles
    def get_career_term_roles
      career_terms = get_active_career_terms

      grouped_roles = grouped_student_plan_roles
      career_term_plan_roles = []

      grouped_roles.keys.each do |role_key|
        student_plan_role = grouped_roles[role_key]
        career_terms.each do |career_term|
          if (student_plan_role[:career_code] == career_term[:acadCareer])
            career_term_plan_roles << student_plan_role.merge({term: career_term.slice(:termId, :termDescr)})
          end
        end
      end
      career_term_plan_roles
    end

    def get_enrollment_term_academic_planner
      plans = {}
      get_active_term_ids.collect do |term_id|
        academic_plan = CampusSolutions::AcademicPlan.new(user_id: @uid, term_id: term_id).get
        plans[term_id] = academic_plan.try(:[], :feed)
      end
      plans
    end

    def get_enrollment_term_instructions
      instructions = {}
      get_active_term_ids.collect do |term_id|
        term_details = CampusSolutions::EnrollmentTerm.new(user_id: @uid, term_id: term_id).get
        instructions[term_id] = term_details.try(:[], :feed).try(:[], :enrollmentTerm)
      end
      instructions
    end

    def user_has_holds?
      !!college_and_level.try(:[], :holds).try(:[], :hasHolds)
    end

    def college_and_level
      worker = Proc.new do
        feed = {}
        MyAcademics::CollegeAndLevel.new(@uid).merge(feed)
        feed.try(:[], :collegeAndLevel)
      end
      @college_and_level ||= worker.call
    end

    def active_plans
      college_and_level.try(:[], :plans)
    end

    def get_active_term_ids
      career_terms = get_active_career_terms
      return [] if career_terms.empty?
      career_terms.collect {|term| term[:termId] }.uniq
    end

    def get_active_career_terms
      get_career_terms = Proc.new do
        terms = CampusSolutions::EnrollmentTerms.new({user_id: @uid}).get
        terms.try(:[], :feed).try(:[], :enrollmentTerms)
      end
      @career_terms ||= get_career_terms.call
    end

    def get_links
      Settings.campus_solutions_links.class_enrollment.as_json['table']
    end

    private

    def user_is_student?
      HubEdos::UserAttributes.new(user_id: @uid).has_role?(:student)
    end
  end
end
