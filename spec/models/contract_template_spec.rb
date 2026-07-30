# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractTemplate, type: :model do
  let(:org) { create(:organization) }

  def template_with(body)
    t = described_class.new(organization: org, name: "T", version: 1)
    t.content = body
    t.save!
    t
  end

  describe "#render_preview" do
    it "replaces {{license_schedule}} with the sample grid (both grids), not the raw token" do
      template = template_with("<div>1.1</div><div>{{license_schedule}}</div>")

      html = template.render_preview

      expect(html).not_to include("{{license_schedule}}")
      expect(html).to include("<th>Dates</th>", "<th>Rent</th>")   # main grid
      expect(html).to include("Payment schedule")                  # payment-due grid
    end

    it "replaces {{services}} with the sample services list" do
      template = template_with("<div>{{services}}</div>")

      html = template.render_preview

      expect(html).not_to include("{{services}}")
      expect(html).to include("Services", "Sound technician")
    end

    it "still fills the plain merge fields" do
      template = template_with("<div>Hello {{contractor_name}}</div>")

      expect(template.render_preview(contractor_name: "Local Troupe")).to include("Local Troupe")
    end
  end
end
