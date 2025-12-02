require 'rails_helper'

RSpec.describe "Shoutout search filters out groups I'm a member of", type: :system do
  let!(:user) { create(:user, password: "password123") }
  let!(:person) { create(:person, user: user, email: user.email_address) }

  it "does not return member groups in search results" do
    member_group = create(:group, name: "MemberGroup")
    other_group = create(:group, name: "OtherMemberGroup")

    # make the person a member of member_group
    member_group.group_memberships.create!(person: person, permission_level: :view)

    sign_in_as_person(user, person)
    visit my_shoutouts_path(tab: "given", show_form: "true")

    # Type a search that would match both groups
    fill_in :search_query, with: "Member"

    # Wait for results to appear
    expect(page).to have_css('[data-shoutout-search-target="results"]', visible: true)

    # The other group should appear, member group should not appear in search results
    within('[data-shoutout-search-target="results"]') do
      expect(page).to have_text(other_group.name)
      # results buttons have data-id attributes for each result
      expect(page).not_to have_css("button[data-id='#{member_group.id}']")
    end
  end
end
