describe Berkeley::DegreeProgressUndergrad do

  describe '#get_status' do
    subject { described_class.get_status(status_code, in_progress_value, is_new_admit_grace_period) }

    context 'when grace period for new admits has ended' do
      let(:is_new_admit_grace_period) { false }

      context 'when in progress is nil' do
        let(:in_progress_value) { nil }
        context 'when status_code is nil' do
          let(:status_code) {nil}
          it {should be nil}
        end
        context 'when status_code is garbage' do
          let(:status_code) {'garbage'}
          it {should eq 'Not Satisfied'}
        end
        context 'when status_code is FAIL' do
          let(:status_code) {'FAIL'}
          it {should eq 'Not Satisfied'}
        end
        context 'when status_code is COMP' do
          let(:status_code) {'COMP'}
          it {should eq 'Satisfied'}
        end
        context 'when status_code is lowercase' do
          let(:status_code) {'comp'}
          it {should eq 'Satisfied'}
        end
      end
      context 'when in progress is \'Y\'' do
        let(:in_progress_value) { 'Y' }
        context 'when status_code is FAIL' do
          let(:status_code) {'FAIL'}
          it {should eq 'Not Satisfied'}
        end
        context 'when status_code is COMP' do
          let(:status_code) {'COMP'}
          it {should eq 'In Progress'}
        end
      end
    end

    context 'when user is a new admit in their grace period' do
      let(:is_new_admit_grace_period) { true }

      context 'when in progress is nil' do
        let(:in_progress_value) { nil }
        context 'when status_code is nil' do
          let(:status_code) {nil}
          it {should be nil}
        end
        context 'when status_code is garbage' do
          let(:status_code) {'garbage'}
          it {should eq 'Under Review'}
        end
        context 'when status_code is FAIL' do
          let(:status_code) {'FAIL'}
          it {should eq 'Under Review'}
        end
        context 'when status_code is COMP' do
          let(:status_code) {'COMP'}
          it {should eq 'Satisfied'}
        end
        context 'when status_code is lowercase' do
          let(:status_code) {'comp'}
          it {should eq 'Satisfied'}
        end
      end
      context 'when in progress is \'Y\'' do
        let(:in_progress_value) { 'Y' }
        context 'when status_code is FAIL' do
          let(:status_code) {'FAIL'}
          it {should eq 'Under Review'}
        end
        context 'when status_code is COMP' do
          let(:status_code) {'COMP'}
          it {should eq 'Under Review'}
        end
      end
    end
  end

  describe '#requirements_whitelist' do
    subject { described_class.requirements_whitelist }
    it {should eq [1, 2, 18, 3]}
  end

  describe '#get_description' do
    subject { described_class.get_description(requirement_code) }

    context 'when requirement_code is nil' do
      let(:requirement_code) {nil}
      it {should be nil}
    end
    context 'when requirement_code is not a number' do
      it 'should raise an error' do
        expect { described_class.get_description('garbage') }.to raise_error(ArgumentError)
      end
    end
    context 'when requirement_code exists in @requirements' do
      let(:requirement_code) {'0000001'}
      it {should eq 'Entry Level Writing'}
    end
  end

  describe '#get_order' do
    subject { described_class.get_order(requirement_code) }

    context 'when requirement_code is nil' do
      let(:requirement_code) {nil}
      it {should be nil}
    end
    context 'when requirement_code is not a number' do
      it 'should raise an error' do
        expect { described_class.get_order('garbage') }.to raise_error(ArgumentError)
      end
    end
    context 'when requirement_code exists in @requirements' do
      let(:requirement_code) {'00002'}
      it {should eq 1}
    end
  end
end
