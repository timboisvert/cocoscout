# frozen_string_literal: true

require "rails_helper"

# Production Home's phone stack (V1.1 plan §4): one line per thing waiting.
RSpec.describe "manage/manage/_needs_attention", type: :view do
  let(:production) { create(:production) }
  let(:show) { create(:show, production: production, date_and_time: Time.zone.local(2026, 10, 23, 21)) }
  let(:role) { Struct.new(:name).new("Improviser") }
  let(:vacancy) { Struct.new(:id, :to_param).new(7, "7") }

  def stack(vacancies: [], audition_signups: 0, attention: nil)
    Nokogiri::HTML.fragment(render(partial: "manage/manage/needs_attention", locals: { vacancies: vacancies, audition_signups: audition_signups, attention: attention }))
  end

  it "draws nothing when nothing is waiting" do
    expect(stack.at_css("[data-needs-attention]")).to be_nil
  end

  it "lists what's waiting, phone only, the one vacancy linking straight to it" do
    doc = stack(vacancies: [ { vacancy: vacancy, show: show, role: role, production: production } ], audition_signups: 3,
                attention: { financials: 2, payouts: 4, payouts_amount: 380, hours: 0 })
    section = doc.at_css("[data-needs-attention]")
    expect(section["class"]).to include("sm:hidden")
    labels = section.css("a").map { |a| a.text.squish }
    expect(labels).to include(a_string_including("Open vacancy", "Improviser, Fri Oct 23"), a_string_including("3 Audition sign-ups to review"),
                              a_string_including("2 Shows that need financials"), a_string_including("To pay", "$380.00 still unpaid"))
    expect(labels.join).not_to include("Hours to approve")
    expect(section.at_css("a")["href"]).to eq(manage_casting_vacancy_path(production, vacancy))
  end
end
