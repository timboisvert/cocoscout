# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailTemplate, type: :model do
  describe "validations" do
    subject { build(:email_template) }

    it "is valid with valid attributes" do
      expect(subject).to be_valid
    end

    it "requires a key" do
      subject.key = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:key]).to include("can't be blank")
    end

    it "requires a unique key" do
      create(:email_template, key: "test_key")
      subject.key = "test_key"
      expect(subject).not_to be_valid
      expect(subject.errors[:key]).to include("has already been taken")
    end

    it "requires a name" do
      subject.name = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:name]).to include("can't be blank")
    end

    it "requires a subject" do
      subject.subject = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:subject]).to include("can't be blank")
    end

    it "requires a body" do
      subject.body = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:body]).to include("can't be blank")
    end
  end

  describe "scopes" do
    it ".active returns only active templates" do
      active = create(:email_template, active: true)
      create(:email_template, active: false)

      expect(EmailTemplate.active).to eq([ active ])
    end

    it ".by_category filters by category" do
      notification = create(:email_template, category: "notification")
      create(:email_template, category: "invitation")

      expect(EmailTemplate.by_category("notification")).to eq([ notification ])
    end
  end

  describe "template types" do
    it "#structured? returns true by default" do
      template = build(:email_template, template_type: nil)
      expect(template.structured?).to be true
    end

    it "#structured? returns true for structured type" do
      template = build(:email_template, template_type: "structured")
      expect(template.structured?).to be true
    end

    it "#passthrough? returns true for passthrough type" do
      template = build(:email_template, template_type: "passthrough")
      expect(template.passthrough?).to be true
      expect(template.structured?).to be false
    end

    it "#hybrid? returns true for hybrid type" do
      template = build(:email_template, template_type: "hybrid")
      expect(template.hybrid?).to be true
      expect(template.structured?).to be false
    end

    it "#template_type_description returns human-readable description" do
      template = build(:email_template, template_type: "passthrough")
      expect(template.template_type_description).to include("passed through")
    end
  end
  describe "#render_subject" do
    it "interpolates variables in the subject" do
      template = build(:email_template, subject: "Hello {{recipient_name}}!")

      result = template.render_subject(recipient_name: "John")

      expect(result).to eq("Hello John!")
    end

    it "handles missing variables gracefully" do
      template = build(:email_template, subject: "Hello {{recipient_name}}!")

      result = template.render_subject({})

      expect(result).to eq("Hello {{recipient_name}}!")
    end
  end

  describe "#render_body" do
    it "interpolates variables in the body" do
      template = build(:email_template, body: "Dear {{name}}, your order {{order_id}} is ready.")

      result = template.render_body(name: "Jane", order_id: "12345")

      expect(result).to eq("Dear Jane, your order 12345 is ready.")
    end

    it "handles variables with extra whitespace" do
      template = build(:email_template, body: "Hello {{ name }}!")

      result = template.render_body(name: "Bob")

      expect(result).to eq("Hello Bob!")
    end
  end

  describe "#variable_names" do
    it "extracts variable names from subject and body" do
      template = build(:email_template,
                       subject: "Hello {{recipient_name}}",
                       body: "Your {{order_id}} for {{product}} is ready.")

      expect(template.variable_names).to contain_exactly("recipient_name", "order_id", "product")
    end

    it "returns unique variable names" do
      template = build(:email_template,
                       subject: "Hello {{name}}",
                       body: "{{name}}, your {{name}} is confirmed.")

      expect(template.variable_names).to eq([ "name" ])
    end
  end

  describe "#variables_with_descriptions" do
    it "returns available variables with descriptions" do
      template = build(:email_template,
                       available_variables: [
                         { name: "recipient", description: "The recipient's name" },
                         { name: "amount", description: "The payment amount" }
                       ])

      result = template.variables_with_descriptions

      expect(result).to eq([
                             { name: "recipient", description: "The recipient's name" },
                             { name: "amount", description: "The payment amount" }
                           ])
    end

    it "handles string-keyed hashes" do
      template = build(:email_template)
      template.available_variables = [
        { "name" => "test", "description" => "A test variable" }
      ]

      result = template.variables_with_descriptions

      expect(result.first[:name]).to eq("test")
      expect(result.first[:description]).to eq("A test variable")
    end
  end
end
