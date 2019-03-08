module Canvas
  class Course < Proxy

    attr_accessor :canvas_course_id

    def initialize(options = {})
      super(options)
      @canvas_course_id = options[:canvas_course_id]
    end

    def course(options = {})
      optional_cache(options, key: @canvas_course_id.to_s, default: true) { wrapped_get request_path }
    end

    def create(account_id, course_name, course_code, term_id, sis_course_id)
      wrapped_post "accounts/#{account_id}/courses", {
        'account_id' => account_id,
        'course' => {
          'name' => course_name,
          'course_code' => course_code,
          'term_id' => term_id,
          'sis_course_id' => sis_course_id
        }
      }
    end

    def official_courses(term_id)
      account_id = Settings.canvas_proxy.official_courses_account_id
      paged_get "accounts/#{account_id}/courses", {
        'enrollment_term_id' => term_id
      }
    end

    def to_s
      "Canvas Course ID #{@canvas_course_id}"
    end

    private

    def request_path
      "courses/#{@canvas_course_id}?include[]=term"
    end

    def mock_json
      read_file('fixtures', 'json', 'canvas_course.json')
    end

  end
end
