module MyAuthenticationHelper
  # Sign in as a person by filling out the login form
  # After sign-in, you'll be on the /my dashboard page
  # Do NOT call visit "/my" again after this - you're already there!
  #
  # Usage:
  #   let!(:user) { create(:user, password: "password123") }
  #
  #   before do
  #     sign_in_as(user)
  #   end
  #
  # Note: This method uses the actual login flow, which makes tests more robust
  # but also slower. System tests typically take 30-60 seconds each.
  def sign_in_as(user, person = nil)
    visit "/signin"
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password123"
    click_button "Sign In"

    # After clicking Sign In, the page will automatically redirect to /my dashboard
    # Wait for the redirect to complete with generous timeout for slow CI environments
    begin
      expect(page).to have_current_path("/my", wait: 20)
      # Also wait for page content to load to ensure JavaScript is ready
      expect(page).to have_content("CocoScout", wait: 10)
    rescue Capybara::ElementNotFound, RSpec::Expectations::ExpectationNotMetError => e
      # If login fails, save a screenshot for debugging
      save_screenshot("tmp/failed_login_#{Time.now.to_i}.png") if respond_to?(:save_screenshot)
      raise "Login failed: #{e.message}. Check if user credentials are correct and database is seeded properly."
    end

    # The session is now established
    # Note: person parameter is accepted for backwards compatibility but not used
  end

  # For backwards compatibility with older tests
  alias_method :sign_in_as_person, :sign_in_as
end

RSpec.configure do |config|
  config.include MyAuthenticationHelper, type: :system
end
