# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrainingCredit, type: :model do
  describe 'associations' do
    it 'belongs to a person' do
      credit = TrainingCredit.new
      expect(credit).to respond_to(:person)
    end
  end

  describe 'validations' do
    let(:person) { create(:person) }

    it 'is invalid without an institution' do
      credit = TrainingCredit.new(person: person, institution: nil, program: 'Acting', year_start: 2020)
      expect(credit).not_to be_valid
      expect(credit.errors[:institution]).to include("can't be blank")
    end

    it 'is invalid with an institution exceeding 200 characters' do
      credit = TrainingCredit.new(person: person, institution: 'A' * 201, program: 'Acting', year_start: 2020)
      expect(credit).not_to be_valid
      expect(credit.errors[:institution]).to be_present
    end

    it 'is invalid without a program' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: nil, year_start: 2020)
      expect(credit).not_to be_valid
      expect(credit.errors[:program]).to include("can't be blank")
    end

    it 'is invalid with a program exceeding 200 characters' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: 'A' * 201, year_start: 2020)
      expect(credit).not_to be_valid
      expect(credit.errors[:program]).to be_present
    end

    it 'is invalid without a year_start' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: nil)
      expect(credit).not_to be_valid
      expect(credit.errors[:year_start]).to include("can't be blank")
    end

    it 'is invalid with year_start before 1900' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: 1899)
      expect(credit).not_to be_valid
      expect(credit.errors[:year_start]).to be_present
    end

    it 'is invalid when year_end is before year_start' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: 2020, year_end: 2019)
      expect(credit).not_to be_valid
      expect(credit.errors[:year_end]).to include("must be greater than or equal to start year")
    end

    it 'validates notes length' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: 2020, notes: 'A' * 1001)
      expect(credit).not_to be_valid
      expect(credit.errors[:notes]).to be_present
    end
  end

  describe '#display_year_range' do
    let(:person) { create(:person) }

    it 'returns just the start year when no end year' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: 2020, year_end: nil, ongoing: false)
      expect(credit.display_year_range).to eq('2020')
    end

    it 'returns just the start year when start equals end' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: 2020, year_end: 2020, ongoing: false)
      expect(credit.display_year_range).to eq('2020')
    end

    it 'returns a range when years differ' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: 2018, year_end: 2020, ongoing: false)
      expect(credit.display_year_range).to eq('2018-2020')
    end
  end

  describe '#display_year_range_with_present' do
    let(:person) { create(:person) }

    it 'shows Present for ongoing credits' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: 2020, ongoing: true)
      expect(credit.display_year_range_with_present).to eq('2020-Present')
    end

    it 'returns just the start year when no end year and not ongoing' do
      credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: 2020, year_end: nil, ongoing: false)
      expect(credit.display_year_range_with_present).to eq('2020')
    end
  end

  describe 'callbacks' do
    let(:person) { create(:person) }

    describe '#set_default_position' do
      it 'sets position to 0 for first credit' do
        credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: 2020, position: nil)
        credit.valid?
        expect(credit.position).to eq(0)
      end

      it 'increments position for subsequent credits' do
        TrainingCredit.create!(person: person, institution: 'University', program: 'Acting', year_start: 2020, position: 0)
        credit = TrainingCredit.new(person: person, institution: 'Another School', program: 'Dance', year_start: 2021, position: nil)
        credit.valid?
        expect(credit.position).to eq(1)
      end
    end

    describe '#clear_year_end_if_ongoing' do
      it 'clears year_end when ongoing is true' do
        credit = TrainingCredit.new(person: person, institution: 'University', program: 'Acting', year_start: 2020, year_end: 2022, ongoing: true)
        credit.valid?
        expect(credit.year_end).to be_nil
      end
    end
  end
end
