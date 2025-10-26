require 'rails_helper'

describe "User registration", type: :system do
  it "allows a user to sign up" do
    visit "/signup"
    fill_in "user_email_address", with: "newuser@example.com"
    fill_in "user_password", with: "password123"
    click_button "Create Account"
    expect(page).to have_content("Shows & Events")
  end
end
