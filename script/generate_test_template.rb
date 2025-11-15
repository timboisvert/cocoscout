#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Template Generator
# Usage: script/generate_test_template.rb ModelName

if ARGV.empty?
  puts "Usage: script/generate_test_template.rb ModelName"
  puts "Example: script/generate_test_template.rb User"
  exit 1
end

model_name = ARGV[0]
model_class = model_name.camelize
model_file = model_name.underscore
spec_file = "spec/models/#{model_file}_spec.rb"

if File.exist?(spec_file)
  puts "❌ Test file already exists: #{spec_file}"
  exit 1
end

template = <<~RUBY
  require 'rails_helper'

  RSpec.describe #{model_class}, type: :model do
    describe "validations" do
      it "is valid with valid attributes" do
        #{model_file} = build(:#{model_file})
        expect(#{model_file}).to be_valid
      end

      # Add validation tests here
      # Example:
      # it "is invalid without a name" do
      #   #{model_file} = build(:#{model_file}, name: nil)
      #   expect(#{model_file}).not_to be_valid
      #   expect(#{model_file}.errors[:name]).to include("can't be blank")
      # end
    end

    describe "associations" do
      # Add association tests here
      # Example:
      # it "belongs to organization" do
      #   #{model_file} = build(:#{model_file})
      #   expect(#{model_file}).to respond_to(:organization)
      # end
    end

    describe "instance methods" do
      # Add tests for instance methods here
      # Example:
      # describe "#full_name" do
      #   it "returns the full name" do
      #     #{model_file} = create(:#{model_file}, first_name: "John", last_name: "Doe")
      #     expect(#{model_file}.full_name).to eq("John Doe")
      #   end
      # end
    end

    describe "class methods" do
      # Add tests for class methods here
      # Example:
      # describe ".active" do
      #   it "returns only active records" do
      #     active = create(:#{model_file}, active: true)
      #     inactive = create(:#{model_file}, active: false)
      #     expect(#{model_class}.active).to include(active)
      #     expect(#{model_class}.active).not_to include(inactive)
      #   end
      # end
    end
  end
RUBY

File.write(spec_file, template)
puts "✅ Created test template: #{spec_file}"
puts ""
puts "Next steps:"
puts "1. Update spec/factories/#{model_file}s.rb if it doesn't exist"
puts "2. Add specific test cases based on your model's validations and methods"
puts "3. Run the tests: bundle exec rspec #{spec_file}"
