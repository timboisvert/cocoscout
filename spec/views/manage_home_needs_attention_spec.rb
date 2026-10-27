# frozen_string_literal: true

require "rails_helper"

# Production Home's phone stack (V1.1 plan §4): one line per thing waiting,
# the same items the desktop status bar draws as pills.
RSpec.describe "manage/manage/_needs_attention", type: :view do
  def stack(items)
    Nokogiri::HTML.fragment(render(partial: "manage/manage/needs_attention", locals: { items: items }))
  end

  it "draws nothing when nothing is waiting" do
    expect(stack([]).at_css("[data-needs-attention]")).to be_nil
  end

  it "lists what's waiting, phone only, the count lifted out of the words" do
    doc = stack([
      { key: "vacancies", tone: :red, text: "1 open vacancy", detail: "Improviser, Fri Oct 23", action: { text: "Review", path: "/manage/casting/1/vacancies/7" } },
      { key: "signups", tone: :pink, text: "3 audition sign-ups to review", action: { text: "Review", path: "/manage/signups" } },
      { key: "financials", tone: :gray, text: "2 shows that need financials", action: { text: "Financials", path: "/manage/money/financials" } },
      { key: "pay", tone: :pink, text: "$380.00 to pay", action: { text: "Pay people", path: "/manage/money/payouts" } },
      { key: "staffing", tone: :amber, text: "Staffing is a draft", action: { text: "Scheduling", modal: "x" } }
    ])
    section = doc.at_css("[data-needs-attention]")
    expect(section["class"]).to include("sm:hidden")
    rows = section.css("[data-status]")
    expect(rows.map { |r| r["data-status"] }).to eq(%w[vacancies signups financials pay staffing])
    expect(rows.first.text.squish).to include("1", "Open vacancy", "Improviser, Fri Oct 23")
    expect(rows.first["href"]).to eq("/manage/casting/1/vacancies/7")
    expect(rows.first["class"]).to include("bg-pink-50")
    expect(rows[1].text.squish).to include("3", "Audition sign-ups to review")
    expect(rows[3].text.squish).to include("$380.00", "To pay")
    expect(rows.last.name).to eq("button")
    expect(rows.last["data-modal-id"]).to eq("x")
  end
end
