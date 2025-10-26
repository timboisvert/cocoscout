require 'rails_helper'

describe "Forgot password", type: :system do
  let!(:user) { create(:user, password: "password123") }

  it "sends a password reset email" do
    visit "/password"
    fill_in "email_address", with: user.email_address
    click_button "Email reset instructions"
    expect(page).to have_content("Sign In", wait: 5)
  end
end
