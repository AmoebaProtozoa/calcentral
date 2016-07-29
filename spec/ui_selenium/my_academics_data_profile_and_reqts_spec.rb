describe 'My Academics profile and university requirements cards', :testui => true do

  if ENV["UI_TEST"] && Settings.ui_selenium.layer != 'production'

    include ClassLogger

    begin
      driver = WebDriverUtils.launch_browser
      test_users = UserUtils.load_test_users.select { |user| user['profile'] }
      testable_users = []
      test_output_heading = ['UID', 'Term Transition', 'Colleges', 'Majors', 'Careers', 'Units', 'GPA', 'Level',
                             'Level No AP', 'Writing', 'History', 'Institutions', 'Cultures']
      test_output = UserUtils.initialize_output_csv(self, test_output_heading)

      splash_page = CalCentralPages::SplashPage.new driver
      status_api_page = ApiMyStatusPage.new driver
      academics_api_page= ApiMyAcademicsPageSemesters.new driver
      profile_card = CalCentralPages::MyAcademicsProfileCard.new driver
      reqts_card = CalCentralPages::MyAcademicsUniversityReqtsCard.new driver

      test_users.each do |user|
        uid = user['uid']
        logger.info "UID is #{uid}"
        term_transition = false
        api_colleges = []
        api_majors = []
        api_careers = []
        api_units = nil
        api_gpa = nil
        api_level = nil
        api_level_no_ap = nil
        api_writing_reqt = nil
        api_history_reqt = nil
        api_institutions_reqt = nil
        api_cultures_reqt = nil

        begin
          splash_page.load_page
          splash_page.basic_auth uid
          status_api_page.get_json driver
          academics_api_page.get_json driver
          profile_card.load_page

          if (status_api_page.has_academics_tab? && status_api_page.is_student?) || status_api_page.has_student_history? || status_api_page.is_applicant?

            profile_card.profile_card_element.when_visible WebDriverUtils.academics_timeout
            testable_users << uid unless academics_api_page.transition_term?

            # NAME
            api_full_name = status_api_page.full_name
            my_academics_full_name = profile_card.name
            it ("show the full name of UID #{uid}") { expect(my_academics_full_name).to eql(api_full_name) }

            # GPA
            if %w(0.0 0).include?(academics_api_page.gpa) || academics_api_page.gpa.nil? || status_api_page.is_concurrent_enroll_student?
              has_gpa = profile_card.gpa?
              it ("show no GPA for UID #{uid}") { expect(has_gpa).to be false }
            else
              api_gpa = academics_api_page.gpa
              shows_gpa = profile_card.gpa_element.visible?
              it ("hide the GPA by default for UID #{uid}") { expect(shows_gpa).to be false }

              profile_card.show_gpa
              gpa_revealed = profile_card.gpa_element.when_visible WebDriverUtils.page_event_timeout
              my_academics_gpa = profile_card.gpa
              it "show the GPA for UID #{uid} when a user clicks 'Show'" do
                expect(gpa_revealed).to be_truthy
                expect(my_academics_gpa).to eql(api_gpa)
              end

              profile_card.hide_gpa
              gpa_hidden = profile_card.gpa_element.when_not_visible WebDriverUtils.page_event_timeout
              it ("hide the GPA for UID #{uid} when a user clicks 'Hide'") { expect(gpa_hidden).to be_truthy }
            end

            # UNITS
            if academics_api_page.ttl_units.nil? || academics_api_page.ttl_units.zero?
              has_units = profile_card.units?
              it ("show no units for UID #{uid}") { expect(has_units).to be false }
            else
              api_units = academics_api_page.ttl_units.to_s
              my_academics_units = profile_card.units
              it ("show the units for UID #{uid}") { expect(my_academics_units).to eql(api_units) }
            end

            # STANDING
            unless academics_api_page.has_no_standing?

              api_colleges = academics_api_page.colleges
              api_majors = academics_api_page.majors
              api_careers = academics_api_page.careers
              api_level = academics_api_page.level
              my_academics_colleges = profile_card.all_colleges
              my_academics_majors = profile_card.all_majors
              my_academics_careers = profile_card.all_careers
              my_academics_level = profile_card.level

              it ("show the colleges for UID #{uid}") { expect(my_academics_colleges).to eql(api_colleges) }
              it ("show the majors for UID #{uid}") { expect(my_academics_majors).to eql(api_majors) }
              it ("show the careers for UID #{uid}") { expect(my_academics_careers).to eql(api_careers) }

              if api_careers.include? 'Graduate'
                it ("do not show 'College of Letters & Science' for grad student UID #{uid}") { expect(my_academics_colleges).not_to include('College of Letters & Science') }
              end

              # LEVEL - AP and NON-AP
              it ("show the level for UID #{uid}") { expect(my_academics_level).to eql(api_level) }
              api_level_no_ap = academics_api_page.non_ap_level
              if api_level_no_ap.nil?
                has_level_no_ap = profile_card.level_non_ap?
                it ("show no level without AP credit for grad UID #{uid}") { expect(has_level_no_ap).to be false }
              else
                my_academics_level_no_ap = profile_card.level_non_ap
                it ("show the level without AP credit for undergrad UID #{uid}") { expect(my_academics_level_no_ap).to eql(api_level_no_ap) }
              end
            end

            # UNDERGRAD REQUIREMENTS

            if academics_api_page.has_no_standing? || (!academics_api_page.careers.include? 'Undergraduate') || academics_api_page.requirements.nil?

              has_reqts_card = reqts_card.reqts_table?
              it ("show no 'University Requirements' UI for UID #{uid}") { expect(has_reqts_card).to be false }

            elsif academics_api_page.requirements.empty?

              has_no_reqts_msg = reqts_card.no_reqts_msg?
              it ("show a 'no requirements' message for UID #{uid}") { expect(has_no_reqts_msg).to be true }

            else

              api_writing_reqt = academics_api_page.requirement_status 'UC Entry Level Writing'

              if api_writing_reqt == 'Completed' || api_writing_reqt == 'Exempt'
                my_academics_writing_met = reqts_card.writing_reqt_met
                it ("show 'UC Entry Level Writing' '#{api_writing_reqt}' for UID #{uid}") { expect(my_academics_writing_met).to eql(api_writing_reqt) }
              else
                my_academics_writing_unmet = reqts_card.writing_reqt_unmet_element.text
                writing_unmet_link_works = WebDriverUtils.verify_external_link(driver, reqts_card.writing_reqt_unmet_element, 'Home | Office of the Registrar')
                it ("show 'UC Entry Level Writing' 'Incomplete' for UID #{uid}") { expect(my_academics_writing_unmet).to include(api_writing_reqt) }
                it ("offers a link to degree requirements for UID #{uid}") { expect(writing_unmet_link_works).to be true }
              end

              api_history_reqt = academics_api_page.requirement_status 'American History'

              if api_history_reqt == 'Completed' || api_history_reqt == 'Exempt'
                my_academics_history_met = reqts_card.history_reqt_met
                it ("show 'American History' '#{api_history_reqt}' for UID #{uid}") { expect(my_academics_history_met).to eql(api_history_reqt) }
              else
                my_academics_history_unmet = reqts_card.history_reqt_unmet_element.text
                history_unmet_link_works = WebDriverUtils.verify_external_link(driver, reqts_card.history_reqt_unmet_element, 'Home | Office of the Registrar')
                it ("show 'American History' 'Incomplete' for UID #{uid}") { expect(my_academics_history_unmet).to include(api_history_reqt) }
                it ("offer a link to degree requirements for UID #{uid}") { expect(history_unmet_link_works).to be true }
              end

              api_institutions_reqt = academics_api_page.requirement_status 'American Institutions'

              if api_institutions_reqt == 'Completed' || api_institutions_reqt == 'Exempt'
                my_academics_institutions_met = reqts_card.institutions_reqt_met
                it("show 'American Institutions' '#{api_institutions_reqt}' for UID #{uid}") { expect(my_academics_institutions_met).to eql(api_institutions_reqt) }
              else
                my_academics_institutions_unmet = reqts_card.institutions_reqt_unmet_element.text
                institutions_unmet_link_works = WebDriverUtils.verify_external_link(driver, reqts_card.institutions_reqt_unmet_element, 'Home | Office of the Registrar')
                it ("show 'American Institutions' 'Incomplete' for UID #{uid}") { expect(my_academics_institutions_unmet).to include(api_institutions_reqt) }
                it ("offer a link to degree requirements for UID #{uid}") { expect(institutions_unmet_link_works).to be true }
              end

              api_cultures_reqt = academics_api_page.requirement_status 'American Cultures'

              if api_cultures_reqt == 'Completed' || api_cultures_reqt == 'Exempt'
                my_academics_cultures_met = reqts_card.cultures_reqt_met
                it ("show 'American Cultures' '#{api_cultures_reqt}' for UID #{uid}") { expect(my_academics_cultures_met).to eql(api_cultures_reqt) }
              else
                my_academics_cultures_unmet = reqts_card.cultures_reqt_unmet_element.text
                cultures_unmet_link_works = WebDriverUtils.verify_external_link(driver, reqts_card.cultures_reqt_unmet_element, 'Home | Office of the Registrar')
                it ("show 'American Cultures' 'Incomplete' for UID #{uid}") { expect(my_academics_cultures_unmet).to include(api_cultures_reqt) }
                it ("offer a link to degree requirements for UID #{uid}") { expect(cultures_unmet_link_works).to be true }
              end
            end

            # STUDENT STATUS MESSAGING VARIATIONS

            if academics_api_page.has_no_standing?

              if status_api_page.is_student?
                if status_api_page.is_registered?
                  has_reg_no_standing_msg = profile_card.reg_no_standing_msg?
                  it ("show a registered but not fully active message to UID #{uid}") { expect(has_reg_no_standing_msg).to be true }
                else
                  if academics_api_page.units_attempted == 0
                    has_non_reg_msg = profile_card.non_reg_student_msg?
                    has_new_student_msg = profile_card.new_student_msg?
                    it ("show a 'not registered' message to UID #{uid}") { expect(has_non_reg_msg).to be true }
                    it ("show a new student message to UID #{uid}") { expect(has_new_student_msg).to be true }
                  else
                    has_non_reg_msg = profile_card.non_reg_student_msg?
                    it ("show a 'not registered' message to UID #{uid}") { expect(has_non_reg_msg).to be true }
                  end
                end

              elsif status_api_page.is_concurrent_enroll_student?
                has_concur_student_msg = profile_card.concur_student_msg?
                has_uc_ext_link = WebDriverUtils.verify_external_link(driver, profile_card.uc_ext_link_element, 'Concurrent Enrollment | Student Services | UC Berkeley Extension')
                has_eap_link = WebDriverUtils.verify_external_link(driver, profile_card.eap_link_element, 'Exchange Students | Berkeley International Office')
                it ("show a concurrent enrollment student message to UID #{uid}") { expect(has_concur_student_msg).to be true }
                it ("show a concurrent enrollment UC Extension link to UID #{uid}") { expect(has_uc_ext_link).to be true }
                it ("show a concurrent enrollment EAP link to UID #{uid}") { expect(has_eap_link).to be true }

              else
                has_ex_student_msg = profile_card.ex_student_msg?
                it ("show an ex-student message to UID #{uid}") { expect(has_ex_student_msg).to be true }
              end

            else

              if academics_api_page.transition_term? && !academics_api_page.trans_term_profile_current?
                term_transition = true
                api_term_transition = "Academic status as of #{academics_api_page.term_name}"
                if status_api_page.is_student?
                  my_academics_term_transition = profile_card.term_transition_heading
                  it ("show the term transition heading to UID #{uid}") { expect(my_academics_term_transition).to eql(api_term_transition) }
                else
                  has_transition_heading = profile_card.term_transition_heading?
                  it ("shows no term transition heading to UID #{uid}") { expect(has_transition_heading).to be false }
                end
              end
            end

          elsif academics_api_page.all_teaching_semesters.nil?

            no_data_msg = profile_card.not_found_element.when_visible WebDriverUtils.page_load_timeout
            it ("show a 'Data not available' message to UID #{uid}") { expect(no_data_msg).to be_truthy }

          else

            has_profile_card = profile_card.profile_card?
            it ("show no profile card to UID #{uid}") { expect(has_profile_card).to be false }
          end

        rescue => e
          logger.error "#{e.message + "\n"} #{e.backtrace.join("\n ")}"
        ensure
          test_output_row = [uid, term_transition, api_colleges * '; ', api_majors * '; ', api_careers * '; ',
                             api_units, api_gpa, api_level, api_level_no_ap, api_writing_reqt, api_history_reqt,
                             api_institutions_reqt, api_cultures_reqt]
          UserUtils.add_csv_row(test_output, test_output_row)
        end
      end

      it ('shows academic profile for a current term for at least one of the test UIDs') { expect(testable_users.any?).to be true }

    rescue => e
      logger.error "#{e.message + "\n"} #{e.backtrace.join("\n ")}"
    ensure
      WebDriverUtils.quit_browser driver
    end
  end
end
