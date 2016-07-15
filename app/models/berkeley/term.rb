module Berkeley
  class Term
    include ActiveAttrModel, ClassLogger
    include Comparable
    extend Cache::Cacheable

    # Legacy SIS term code, only used for integration with legacy DB sources.
    attr_reader :code
    # CS term ID.
    attr_reader :campus_solutions_id
    attr_reader :name
    attr_reader :slug
    attr_reader :year
    # The Academic Calendar shows Fall/Spring semesters beginning one week before classes.
    attr_reader :start
    # The Fall/Spring semesters end two weeks after the end of formal classes.
    attr_reader :end
    attr_reader :classes_start
    attr_reader :classes_end
    # The end of instruction is one week after classes end. The week between is RRR week. The week after is for final exams.
    attr_reader :instruction_end
    # BearFacts and related systems set "CT"/"Current Term" to Fall (and "FT"/"Future Term" to
    # the next year's Spring) as soon as the Spring term is over. Summer terms are special-cased as
    # "CS" or "FS", and lack some SIS support. This quirk becomes important when configuring
    # certain queries, notably Tele-BEARS appointments.
    attr_reader :legacy_sis_term_status
    # returns true for the Summer term, false otherwise
    attr_reader :is_summer
    # The raw data source.
    attr_reader :raw_source

    FALL_2016_DATES = {
      'term_start_date' => Time.parse('2016-08-24 00:00:00 UTC'),
      'term_end_date' => Time.parse('2016-12-09 00:00:00 UTC')
    }

    def initialize(db_row = nil)
      from_legacy_db(db_row) if db_row.present?
    end

    def from_cs_api(api_feed)
      @raw_source = api_feed
      # The HubTerm API returns an array of matching terms, one for each applicable academic career. For general
      # campus-wide reference, we pick the Undergraduate entry.
      term_feed = api_feed.select {|t| t['academicCareer']['code'] == 'UGRD'}.first
      if term_feed.nil?
        logger.error "No term match found for academicCareer UGRD in feed #{api_feed}; will use first term instead"
        term_feed = api_feed.first
      end
      @campus_solutions_id = term_feed['id']
      (term_yr, @code) = TermCodes.from_edo_id(@campus_solutions_id).values
      @year = term_yr.to_i
      @slug = TermCodes.to_slug(@year, @code)
      @name = Berkeley::TermCodes.codes[@code.to_sym]
      @start = term_feed['beginDate'].to_date.in_time_zone.to_datetime
      @end = term_feed['endDate'].to_date.in_time_zone.to_datetime.end_of_day
      @is_sis_current_term = term_feed['temporalPosition'] == 'Current'
      if @code == 'C'
        @is_summer = true
        @classes_start = @start
        @classes_end = @end
        @instruction_end = @end
      else
        @is_summer = false
        session = term_feed['sessions'].first
        @classes_start = session['beginDate'].to_date.in_time_zone.to_datetime
        @instruction_end = session['endDate'].to_date.in_time_zone.to_datetime.end_of_day
        @classes_end = @instruction_end.advance(days: -7)
      end
      self
    end

    def from_legacy_db(db_row)
      term_cd = db_row['term_cd']
      term_yr = db_row['term_yr'].to_i
      @code = term_cd
      @year = term_yr
      @name = db_row['term_name']
      @slug = TermCodes.to_slug(term_yr, term_cd)
      @campus_solutions_id = TermCodes.to_edo_id(term_yr, term_cd)

      # TODO Remove this embarrassment as soon as we switch to Campus Solutions for source of record on term dates.
      db_row.merge! FALL_2016_DATES if @slug == 'fall-2016'

      @classes_start = db_row['term_start_date'].to_date.in_time_zone.to_datetime
      @instruction_end = db_row['term_end_date'].to_date.in_time_zone.to_datetime.end_of_day
      @legacy_sis_term_status = db_row['term_status']
      if term_cd == 'C'
        @start = @classes_start
        @end = @instruction_end
        @classes_end = @instruction_end
        @is_summer = true
      else
        @start = @classes_start.advance(days: -7)
        @end = @instruction_end.advance(days: 7)
        @classes_end = @instruction_end.advance(days: -7)
        @is_summer = false
      end
      self
    end

    def to_english
      TermCodes.to_english(year, code)
    end

    def <=>(other_term)
      campus_solutions_id <=> other_term.campus_solutions_id
    end

    def sis_current_term?
      @is_sis_current_term
    end

    def legacy?
      @campus_solutions_id <= TermCodes.slug_to_edo_id(Settings.terms.legacy_cutoff)
    end

    # Most final grades should appear on the transcript by this date.
    def grades_entered
      @end.advance(weeks: 4)
    end

    def to_h
      methods = [:campus_solutions_id, :name, :year, :code, :slug, :to_english,
        :start, :end, :classes_start, :classes_end, :instruction_end, :grades_entered,
        :is_summer, :legacy?]
      Hash[methods.collect {|m| [m, send(m)]}]
    end

    def to_s
      "#<Berkeley::Term> #{to_h}"
    end
  end
end
