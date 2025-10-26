require 'capybara/rspec'
require 'selenium-webdriver'

Capybara.server = :puma, { Silent: true }

# Register Chrome headless driver for system tests
Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1400,1400')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

# Use headless Chrome for JavaScript-enabled tests
Capybara.javascript_driver = :headless_chrome

# Set default driver for all system tests
Capybara.default_driver = :headless_chrome

# Increase wait time for elements to appear (helps with async operations)
Capybara.default_max_wait_time = 5
