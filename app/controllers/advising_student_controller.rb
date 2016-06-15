class AdvisingStudentController < ApplicationController
  include CampusSolutions::StudentLookupFeatureFlagged
  include AdvisorAuthorization

  before_action :api_authenticate
  before_action :authorize_student_lookup

  rescue_from StandardError, with: :handle_api_exception
  rescue_from Errors::ClientError, with: :handle_client_error
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def profile
    student_uid = student_uid_param
    render json: {
      attributes: User::AggregatedAttributes.new(student_uid).get_feed,
      contacts: HubEdos::Contacts.new(user_id: student_uid, include_fields: %w(names addresses phones emails)).get
    }
  end

  def academics
    render json: filtered_academics.to_json
  end

  def enrollment_term
    model = CampusSolutions::MyEnrollmentTerm.new student_uid_param
    model.term_id = params['term_id']
    render json: model.get_feed_as_json
  end

  def enrollment_terms
    render json: CampusSolutions::MyEnrollmentTerms.new(student_uid_param).get_feed_as_json
  end

  def academic_plan
    render json: academic_plan_by_student_uid.get_feed_as_json
  end

  def holds
    render json: CampusSolutions::MyHolds.new(student_uid_param).get_feed_as_json
  end

  def resources
    json = CampusSolutions::AdvisingResources.new(user_id: session['user_id'], student_uid: student_uid_param).get
    links = json[:feed] && json[:feed][:ucAdvisingResources] && json[:feed][:ucAdvisingResources][:ucAdvisingLinks]
    if links
      # Advisors get only a subset of links
      keys = [:ucServiceIndicator, :ucStudentAdvisor, :multiYearAcademicPlannerStudentSpecific, :schedulePlannerStudentSpecific]
      advising_links = links.select { |key| keys.include? key }
      json[:feed][:ucAdvisingResources][:ucAdvisingLinks] = advising_links
    end
    render json: json
  end

  private

  def filtered_academics
    feed = MyAcademics::Merged.from_session('user_id' => student_uid_param).get_feed
    if (semesters = feed[:semesters])
      semesters.each do |s|
        s.delete :slug
        (classes = s[:classes]) && classes.each do |c|
          c.delete :slug
          c.delete :url
          (sections = c[:sections]) && sections.each do |section|
            section.delete :url
          end
        end
      end
    end
    (memberships = feed[:otherSiteMemberships]) && memberships.each do |membership|
      membership.delete :slug
      membership[:sites].each { |site| site.delete :site_url } if membership[:sites]
    end
    feed
  end

  def academic_plan_by_student_uid
    model = CampusSolutions::MyAcademicPlan.new student_uid_param
    model.term_id = params['term_id']
    model
  end

  def authorize_student_lookup
    raise NotAuthorizedError.new('The student lookup feature is disabled') unless is_feature_enabled
    authorize_advisor_view_as current_user.real_user_id, student_uid_param
  end

  def student_uid_param
    params.require 'student_uid'
  end

end
