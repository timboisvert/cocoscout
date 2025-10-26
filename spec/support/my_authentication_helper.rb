module MyAuthenticationHelper
  # Sign in as a person by filling out the login form
  # After sign-in, you'll be on the /my dashboard page
  # Do NOT call visit "/my" again after this - you're already there!
  def sign_in_as(user, person = nil)
    visit "/signin"
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password123"
    click_button "Sign In"
    # After clicking Sign In, the page will automatically redirect to /my dashboard
    # Wait for the redirect to complete - increased timeout and added explicit wait
    expect(page).to have_current_path("/my", wait: 15)
    # Also wait for page content to load
    expect(page).to have_content("CocoScout", wait: 5)
    # The session is now established
    # Note: person parameter is accepted for backwards compatibility but not used
  end

  # For backwards compatibility
  alias_method :sign_in_as_person, :sign_in_as
end

RSpec.configure do |config|
  config.include MyAuthenticationHelper, type: :system
end
