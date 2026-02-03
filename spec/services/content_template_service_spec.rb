# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContentTemplateService do
  before do
    # Clear any existing templates from seeds
    ContentTemplate.destroy_all
  end

  describe ".render" do
    let!(:template) do
      create(:content_template,
             key: "test_template",
             subject: "Hello {{recipient_name}}!",
             body: "Dear {{recipient_name}}, welcome to {{company}}.")
    end

    it "renders a template with variables" do
      result = ContentTemplateService.render("test_template", {
                                               recipient_name: "John",
                                               company: "CocoScout"
                                             })

      expect(result[:subject]).to eq("Hello John!")
      expect(result[:body]).to eq("Dear John, welcome to CocoScout.")
    end

    it "raises error for non-existent template" do
      expect {
        ContentTemplateService.render("nonexistent")
      }.to raise_error(ContentTemplateService::TemplateNotFoundError)
    end

    context "with strict mode" do
      it "raises error for missing variables" do
        expect {
          ContentTemplateService.render("test_template", { recipient_name: "John" }, strict: true)
        }.to raise_error(ContentTemplateService::MissingVariablesError, /company/)
      end

      it "passes when all variables provided" do
        expect {
          ContentTemplateService.render("test_template",
                                        { recipient_name: "John", company: "Acme" },
                                        strict: true)
        }.not_to raise_error
      end
    end
  end

  describe ".exists?" do
    it "returns true for existing active template" do
      create(:content_template, key: "existing", active: true)

      expect(ContentTemplateService.exists?("existing")).to be true
    end

    it "returns false for inactive template" do
      create(:content_template, key: "inactive", active: false)

      expect(ContentTemplateService.exists?("inactive")).to be false
    end

    it "returns false for non-existent template" do
      expect(ContentTemplateService.exists?("nonexistent")).to be false
    end
  end

  describe ".upsert" do
    it "creates a new template" do
      template = ContentTemplateService.upsert("new_template",
                                               name: "New Template",
                                               subject: "Hello",
                                               body: "World")

      expect(template).to be_persisted
      expect(template.key).to eq("new_template")
      expect(template.name).to eq("New Template")
    end

    it "updates existing template" do
      create(:content_template, key: "existing", name: "Old Name")

      template = ContentTemplateService.upsert("existing", name: "New Name")

      expect(template.name).to eq("New Name")
      expect(ContentTemplate.where(key: "existing").count).to eq(1)
    end
  end

  describe ".preview" do
    let!(:template) do
      create(:content_template,
             key: "preview_test",
             subject: "Hello {{recipient_name}}!",
             body: "Welcome {{recipient_name}} to {{company_name}}.",
             available_variables: [
               { name: "recipient_name", description: "Recipient's name" },
               { name: "company_name", description: "Company name" }
             ])
    end

    it "returns preview with sample data" do
      result = ContentTemplateService.preview("preview_test")

      # Sample values now use more realistic names based on variable name patterns
      expect(result[:subject]).to include("Sarah Johnson") # Sample value for recipient_name
      expect(result[:variables_used]).to contain_exactly("recipient_name", "company_name")
      expect(result[:available_variables]).to be_present
    end

    it "accepts custom sample variables" do
      result = ContentTemplateService.preview("preview_test",
                                              recipient_name: "Jane Doe",
                                              company_name: "Acme Corp")

      expect(result[:subject]).to eq("Hello Jane Doe!")
      expect(result[:body]).to include("Acme Corp")
    end
  end
  end
