# frozen_string_literal: true

require "rails_helper"

# A show canceled, taken away or moved: its cast and staff are recorded, Tell
# people sends to each (seen and edited first), the shifts come off or move
# with it when the manager says so, and Home says whether they were told
# (docs/show_change_notices_plan.md, Tim 2026-10-30).
RSpec.describe "Telling people a show changed", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars & Garters") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Mr. Mystery Machine") }
  let(:other) { create(:production, organization: org, name: "Bloody Bodies") }

  let(:week_start) { Date.current.beginning_of_week + 1.week }
  let(:saturday) { week_start + 5 }
  let!(:seven) { create(:show, production: production, date_and_time: saturday.in_time_zone.change(hour: 19), duration_minutes: 60) }
  let!(:nine) { create(:show, production: other, date_and_time: saturday.in_time_zone.change(hour: 21), duration_minutes: 60) }

  let(:ana) { create(:person, name: "Ana Ruiz", user: create(:user)) }
  let(:tess) { create(:person, name: "Tess Ng", user: create(:user)) }
  let(:miles) { create(:person, name: "Miles Rowe", user: create(:user)) }
  let(:booth) { create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific) }
  let(:bartender) { create(:house_role, organization: org, name: "Bartender", role_type: :house) }
  let!(:booth_shift) do
    create(:shift, organization: org, house_role: booth, source: seven, starts_at: seven.date_and_time - 30.minutes, ends_at: seven.ends_at)
  end
  let!(:bar_shift) do
    create(:shift, organization: org, house_role: bartender,
                   starts_at: saturday.in_time_zone.change(hour: 18), ends_at: saturday.in_time_zone.change(hour: 23, min: 59))
  end

  before do
    org.people << [ ana, tess, miles ]
    create(:show_person_role_assignment, show: seven, assignable: ana)
    booth_shift.shift_assignments.create!(person: tess)
    bar_shift.shift_assignments.create!(person: miles)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def tell(batch, section, people, shift_action: "0")
    page = Nokogiri::HTML(response.body)
    form = page.at_css("[data-tell-section='#{section}'] form")
    post manage_tell_show_changes_path(batch), params: {
      section: section, person_ids: people.map(&:id), shift_action: shift_action,
      subject: form.at_css("input[name='subject']")["value"], body: form.at_css("input[name='body']")["value"]
    }
    expect(response).to redirect_to(manage_show_changes_path(batch))
    follow_redirect!
  end

  def home_chip(show, key)
    get manage_path(week_start: week_start.to_s)
    Nokogiri::HTML(response.body).at_css("[data-home-week] [data-home-show='#{show.id}'] [data-chip='#{key}']")
  end

  it "takes a cancel to Tell people, tells the cast and the show's own staff, and takes the shift off" do
    # Stored as plain text with line breaks, as the real one is.
    ContentTemplate.find_by!(key: "show_canceled").update!(body: "Hello, {{recipient_name}}\n\nCanceled:\n\n{{production_name}}\n{{event_date}}")
    patch manage_cancel_show_path(production, seven), params: { scope: "this" }
    change = ShowChange.last
    expect(change).to have_attributes(kind: "canceled", show_id: seven.id)
    expect(change.cast_person_ids).to eq([ ana.id ])
    # The bartender works the whole night, and Bloody Bodies is still on.
    expect(change.staff_person_ids).to eq([ tess.id ])
    expect(response).to redirect_to(manage_show_changes_path(change.batch))

    expect(home_chip(seven, "cast").text).to include("Cast not notified")
    expect(home_chip(seven, "staffing").text).to include("Staff not notified")

    get manage_show_changes_path(change.batch)
    page = Nokogiri::HTML(response.body)
    expect(page.css("[data-tell-section]").map { |s| s["data-tell-section"] }).to eq(%w[cast_off staff_off])
    expect(page.at_css("[data-tell-section='cast_off']").text).to include("Ana Ruiz")
    expect(page.at_css("[data-tell-section='staff_off']").text).to include("Tess Ng", "Take these shifts off")
    # One person each: their lines are in the draft itself, as paragraphs, not
    # left as placeholders.
    staff_draft = page.at_css("[data-tell-section='staff_off'] input[name='body']")["value"]
    expect(staff_draft).to include("<p>", "Booth Tech, #{saturday.strftime('%a, %b %-d')}, 6:30–8:00 PM")
    expect(staff_draft).not_to include("{{shifts}}")
    expect(page.at_css("[data-tell-section='cast_off'] input[name='body']")["value"])
      .to include("<p>Hello, {{recipient_name}}</p>", "<p>Mr. Mystery Machine<br>", "#{saturday.strftime('%a, %b %-d')}, 7:00 PM")
    expect(page.at_css("[data-filled-in]")).to be_nil
    expect(page.text).not_to include("Miles Rowe")

    # Notify staff opens just the staff.
    get manage_show_changes_path(change.batch, audience: "staff")
    expect(Nokogiri::HTML(response.body).css("[data-tell-section]").map { |s| s["data-tell-section"] }).to eq(%w[staff_off])
    get manage_show_changes_path(change.batch)

    expect { tell(change.batch, "cast_off", [ ana ]) }.to change { ana.user.notifications.count }.by(1)
    expect(ShowChangeNotice.where(show_change: change, audience: "cast").pluck(:person_id)).to eq([ ana.id ])
    expect(Nokogiri::HTML(response.body).at_css("[data-tell-section='cast_off']")).to be_nil

    tell(change.batch, "staff_off", [ tess ], shift_action: "1")
    expect(booth_shift.reload).to be_not_needed
    expect(booth_shift.shift_assignments).to be_empty
    expect(response.body).to include("Everyone has been notified.")

    expect(home_chip(seven, "cast").text).to include("Cast notified")
    expect(home_chip(seven, "staffing").text).to include("Staff notified")
  end

  it "shows on the cancel screen exactly who each way of canceling would notify" do
    series = SecureRandom.uuid
    seven.update!(recurrence_group_id: series)
    later = create(:show, production: production, date_and_time: seven.date_and_time + 1.week, duration_minutes: 60, recurrence_group_id: series)
    create(:show_person_role_assignment, show: later, assignable: miles)

    get manage_cancel_show_form_path(production, seven)
    page = Nokogiri::HTML(response.body)
    this = page.at_css("[data-cancel-notify-people] [data-scope='this']")
    expect(this.at_css("[data-notify-box='cast']").text).to include("Ana Ruiz")
    expect(this.at_css("[data-notify-box='cast']").text).not_to include("Miles Rowe")
    expect(this.at_css("[data-notify-box='staff']").text).to include("Tess Ng", "Booth Tech")
    future = page.at_css("[data-cancel-notify-people] [data-scope='this_and_future']")
    expect(future["class"]).to include("hidden")
    expect(future.at_css("[data-notify-box='cast']").text).to include("Ana Ruiz", "Miles Rowe")
    expect(future.text).to include("Across the 2 dates still to come")
  end

  it "counts the night's crew in when the last show of the night goes" do
    nine.update!(canceled: true)
    patch manage_cancel_show_path(production, seven), params: { scope: "this" }
    change = ShowChange.where(show: seven).last
    expect(change.staff_person_ids).to contain_exactly(tess.id, miles.id)

    # Their shifts differ, so {{shifts}} stays in the draft and each person's
    # version is listed under it.
    get manage_show_changes_path(change.batch, audience: "staff")
    section = Nokogiri::HTML(response.body).at_css("[data-tell-section='staff_off']")
    expect(section.at_css("input[name='body']")["value"]).to include("{{shifts}}")
    expect(section.at_css("[data-filled-in]").text).to include("Tess Ng:", "Booth Tech", "Miles Rowe:", "Bartender")
  end

  it "records a move, and moves the shifts with the show when the manager says so" do
    seven.update!(date_and_time: seven.date_and_time + 1.hour)
    change = ShowChange.last
    expect(change).to have_attributes(kind: "moved", was_starts_at: saturday.in_time_zone.change(hour: 19),
                                      now_starts_at: saturday.in_time_zone.change(hour: 20))
    expect(home_chip(seven, "cast").text).to include("Cast not notified")

    get manage_show_changes_path(change.batch)
    expect(Nokogiri::HTML(response.body).css("[data-tell-section]").map { |s| s["data-tell-section"] }).to eq(%w[cast_moved staff_moved])
    # The draft shows the shift at its new time, as it will be once moved.
    expect(Nokogiri::HTML(response.body).at_css("[data-tell-section='staff_moved'] input[name='body']")["value"]).to include("6:30–8:00 PM → 7:30–9:00 PM")
    tell(change.batch, "staff_moved", [ tess ], shift_action: "1")
    expect(booth_shift.reload.starts_at).to eq(saturday.in_time_zone.change(hour: 19, min: 30))
    tell(change.batch, "cast_moved", [ ana ])

    # Everyone notified: the move no longer shows on Home.
    expect(home_chip(seven, "cast").text).not_to include("notified")
  end

  it "keeps who a deleted show had, and offers Tell people on the next page" do
    delete manage_delete_show_path(production, seven), params: { scope: "this" }
    change = ShowChange.last
    expect(change).to have_attributes(kind: "removed", show_id: nil, show_label: "Mr. Mystery Machine · #{saturday.strftime('%a, %b %-d')}, 7:00 PM")
    expect(change.cast_person_ids).to eq([ ana.id ])

    follow_redirect!
    notice = Nokogiri::HTML(response.body).at_css("[data-show-changes-notice]")
    expect(notice.text).to include("took 1 date off", "haven't been notified", "Notify them")
    expect(notice.at_css("a")["href"]).to eq(manage_show_changes_path(change.batch))

    get manage_show_changes_path(change.batch)
    expect(response.body).to include("Taken off", "Ana Ruiz", "Tess Ng")
  end

  it "records nothing for a show in the past, or one nobody is on" do
    past = create(:show, production: production, date_and_time: 2.days.ago, duration_minutes: 60)
    create(:show_person_role_assignment, show: past, assignable: ana)
    lonely = create(:show, production: other, date_and_time: 3.weeks.from_now, duration_minutes: 60)
    expect {
      past.update!(canceled: true)
      lonely.update!(canceled: true)
    }.not_to change(ShowChange, :count)
  end

  it "closes a waiting cancel when the show is brought back" do
    seven.update!(canceled: true)
    seven.update!(canceled: false)
    expect(ShowChange.last.closed_at).to be_present
  end

  it "lets a show canceled before this be told from Home" do
    seven.update_column(:canceled, true)
    expect(home_chip(seven, "cast").text).to include("Cast not notified")
    expect(ShowChange.count).to eq(0)

    post manage_tell_canceled_show_path(seven)
    change = ShowChange.last
    expect(change).to have_attributes(kind: "canceled", show_id: seven.id)
    expect(response).to redirect_to(manage_show_changes_path(change.batch))
  end

  it "won't open a batch for someone who can't manage its production" do
    seven.update!(canceled: true)
    stranger = create(:user, password: password)
    create(:organization_role, user: stranger, organization: org)
    post handle_signin_path, params: { email_address: stranger.email_address, password: password }
    get manage_show_changes_path(ShowChange.last.batch)
    expect(response).to redirect_to(manage_path)
  end
end
