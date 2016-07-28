describe CampusOracle::Calendar do

  describe '#get_all_courses' do
    context 'getting all courses regardless of enrollment' do
      subject { CampusOracle::Calendar.get_all_courses }
      it 'returns a list of courses in the configured departments' do
        expect(subject).to be
        if CampusOracle::Calendar.test_data?
          expect(subject.length).to be >= 1
        end
      end
      it 'should respect business rule about print_cd of A in class schedule data' do
        if CampusOracle::Calendar.test_data?
          expect(subject.length).to eq 5
        end
      end
    end
  end

  describe '#get_whitelisted_students' do
    subject { CampusOracle::Calendar.get_whitelisted_students(users, term_yr, term_cd, ccn) }
    let(:term_yr) { 2013 }
    let(:term_cd) { 'D' }
    let(:ccn) { 7309 }

    context 'with a user in the whitelist' do
      let(:users) {
        user = Calendar::User.create({uid: 300939})
        [user]
      }
      it 'returns a list of email addresses for whitelisted users in the specified course' do
        expect(subject).to be
        if CampusOracle::Calendar.test_data?
          expect(subject.length).to be >= 1
        end
      end
    end

    context 'with an empty whitelist' do
      subject { CampusOracle::Calendar.get_whitelisted_students([], term_yr, term_cd, ccn) }
      it 'returns an empty list' do
        expect(subject).to be_empty
      end
    end
  end

  describe '#terms' do
    subject { CampusOracle::Calendar.terms }
    context 'in Spring 2013' do
      before(:each) { Settings.terms.stub(:fake_now).and_return(DateTime.parse('2013-03-10')) }
      it 'should return Spring 2013 and Fall 2013' do
        expect(subject[0].slug).to eq 'spring-2013'
        expect(subject[1].slug).to eq 'summer-2013'
        expect(subject[2].slug).to eq 'fall-2013'
      end
    end
    context 'in Summer 2013' do
      before(:each) { Settings.terms.stub(:fake_now).and_return(DateTime.parse('2013-07-10')) }
      it 'should return Summer 2013 and Fall 2013' do
        expect(subject[0].slug).to eq 'summer-2013'
        expect(subject[1].slug).to eq 'fall-2013'
        expect(subject[2].slug).to eq 'spring-2014'
      end
    end
    context 'in Fall 2013' do
      before(:each) { Settings.terms.stub(:fake_now).and_return(DateTime.parse('2013-10-10')) }
      it 'should return Fall 2013 and Spring 2014' do
        expect(subject[0].slug).to eq 'fall-2013'
        expect(subject[1].slug).to eq 'spring-2014'
        expect(subject[2].slug).to eq 'summer-2014'
      end
    end
    # Summer 2016 is the last term in the fake test data for CALCENTRAL_TERM_INFO_VW)
    context 'in Summer 2016' do
      before(:each) { Settings.terms.stub(:fake_now).and_return(DateTime.parse('2016-7-10')) }
      it 'should return Summer 2016' do
        expect(subject[0].slug).to eq 'summer-2016'
      end
      it 'should screen out nil values for terms not in database' do
        if CampusOracle::Calendar.test_data?
          expect(subject).to have(1).item
        end
      end
    end
  end

end
