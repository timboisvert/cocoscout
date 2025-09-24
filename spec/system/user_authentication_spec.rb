require 'rails_helper'

describe "User authentication", type: :system do
  let!(:user) { create(:user, password: "password123") }

  it "allows a user to sign in" do
    visit "/signin"
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password123"
    click_button "Sign In"
    expect(page).to have_content("Add your Production Company")
  end

  it "allows a user to sign out" do
    visit "/signin"
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password123"
    click_button "Sign In"
    visit "/signout"
    expect(page).to have_content("Sign In")
  end

  it "shows error for invalid login" do
    visit "/signin"
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "wrongpassword"
    click_button "Sign In"
    expect(page).to have_content("Sign In")
  end
end
