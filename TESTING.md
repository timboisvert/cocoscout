# Testing Guide for CocoScout

This guide provides best practices and examples for writing tests in CocoScout.

## Quick Links
- **[Test Performance Guide](TEST_PERFORMANCE.md)** - Understanding test types and optimization strategies
- **[Generate Test Template](#generating-test-templates)** - Quick start for new model tests

## Table of Contents
- [Running Tests](#running-tests)
- [Test Types](#test-types)
- [Writing Model Tests](#writing-model-tests)
- [Writing Request Tests](#writing-request-tests)
- [Writing System Tests](#writing-system-tests)
- [Using Factories](#using-factories)
- [Common Patterns](#common-patterns)
- [Troubleshooting](#troubleshooting)

## Running Tests

### Run all tests
```bash
bundle exec rspec
```

### Run specific test types
```bash
# Model tests only (fast)
bundle exec rspec spec/models/

# Request tests only (integration tests)
bundle exec rspec spec/requests/

# System tests only (end-to-end tests with browser - slow)
bundle exec rspec spec/system/
```

### Run a specific test file
```bash
bundle exec rspec spec/models/user_spec.rb
```

### Run a specific test
```bash
bundle exec rspec spec/models/user_spec.rb:10
```

## Test Types

### 1. Model Tests (`spec/models/`)
- **Purpose**: Test model validations, associations, methods, and business logic
- **Speed**: Fast (no database transactions)
- **When to use**: Always test models - they're the core of your application

### 2. Request Tests (`spec/requests/`)
- **Purpose**: Test API endpoints and controller actions
- **Speed**: Medium
- **When to use**: Test important API endpoints and controller logic

### 3. System Tests (`spec/system/`)
- **Purpose**: End-to-end tests that simulate user interaction in a browser
- **Speed**: Slow (requires Chrome/browser startup)
- **When to use**: Test critical user flows and integration between components

## Writing Model Tests

Model tests should cover:
- Validations
- Associations
- Instance methods
- Class methods
- Callbacks
- Scopes

### Example: Basic Model Test

```ruby
require 'rails_helper'

RSpec.describe User, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      user = build(:user)
      expect(user).to be_valid
    end

    it "is invalid without an email_address" do
      user = build(:user, email_address: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email_address]).to include("can't be blank")
    end

    it "is invalid with a duplicate email_address" do
      create(:user, email_address: "test@example.com")
      duplicate_user = build(:user, email_address: "test@example.com")
      expect(duplicate_user).not_to be_valid
    end
  end

  describe "associations" do
    it { should belong_to(:person).optional }
    it { should have_many(:user_roles) }
    it { should have_many(:organizations).through(:user_roles) }
  end

  describe "#full_name" do
    it "returns the person's name when person exists" do
      person = create(:person, name: "John Doe")
      user = create(:user, person: person)
      expect(user.full_name).to eq("John Doe")
    end

    it "returns email when person doesn't exist" do
      user = create(:user, email_address: "test@example.com", person: nil)
      expect(user.full_name).to eq("test@example.com")
    end
  end
end
```

## Writing Request Tests

Request tests verify that your controllers respond correctly to HTTP requests.

### Example: Request Test

```ruby
require 'rails_helper'

RSpec.describe "Productions", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:production) { create(:production, organization: organization) }

  before do
    # Sign in the user (session-based authentication)
    post signin_path, params: { 
      email_address: user.email_address, 
      password: "password123" 
    }
  end

  describe "GET /manage/productions/:id" do
    it "returns a successful response" do
      get manage_production_path(production)
      expect(response).to have_http_status(:success)
    end

    it "displays the production name" do
      get manage_production_path(production)
      expect(response.body).to include(production.name)
    end
  end

  describe "POST /manage/productions" do
    it "creates a new production" do
      expect {
        post manage_productions_path, params: {
          production: {
            name: "New Production",
            organization_id: organization.id
          }
        }
      }.to change(Production, :count).by(1)
    end

    it "redirects to the production page" do
      post manage_productions_path, params: {
        production: {
          name: "New Production",
          organization_id: organization.id
        }
      }
      expect(response).to redirect_to(manage_production_path(Production.last))
    end
  end
end
```

## Writing System Tests

System tests use Capybara to simulate real user interactions in a headless Chrome browser.

### Important: Authentication Helper

Use the `sign_in_as` helper for system tests:

```ruby
require 'rails_helper'

RSpec.describe "User Dashboard", type: :system do
  let!(:user) { create(:user, password: "password123") }

  before do
    # This helper signs in the user and waits for the redirect
    sign_in_as(user)
  end

  it "displays the dashboard" do
    # After sign_in_as, you're already on the /my dashboard
    expect(page).to have_content("Shows & Events")
  end
end
```

### Example: Complete System Test

```ruby
require 'rails_helper'

RSpec.describe "Production Management", type: :system do
  let!(:user) { create(:user, password: "password123") }
  let!(:organization) { create(:organization, owner: user) }

  before do
    sign_in_as(user)
  end

  it "allows creating a new production" do
    visit manage_select_path
    click_link organization.name
    
    click_link "New Production"
    
    fill_in "Name", with: "My New Show"
    fill_in "Contact Email", with: "contact@example.com"
    click_button "Create Production"
    
    expect(page).to have_content("My New Show")
    expect(page).to have_content("Production created successfully")
  end
end
```

### System Test Tips

1. **Always use `sign_in_as(user)` helper** - Don't manually visit signin and fill forms
2. **Don't visit `/my` after signing in** - The helper already redirects you there
3. **Wait for elements**: Use `expect(page).to have_content()` which waits automatically
4. **Use descriptive expectations**: Be specific about what you're looking for
5. **Keep tests focused**: One user flow per test

## Using Factories

We use FactoryBot to create test data. Factories are defined in `spec/factories/`.

### Factory Basics

```ruby
# Build an object (not saved to database)
user = build(:user)

# Create an object (saved to database)
user = create(:user)

# Create with custom attributes
user = create(:user, email_address: "custom@example.com")

# Build with associations
production = build(:production, organization: organization)
```

### Factory Traits

Some factories have traits for common variations:

```ruby
# Example with traits (if defined)
question = create(:question, :required)
audition_cycle = create(:audition_cycle, :video_upload)
```

### Creating Associated Records

```ruby
# Create a production with an organization owner
organization = create(:organization)  # Creates organization with owner
production = create(:production, organization: organization)

# Create a show with all associations
show = create(:show, production: production)
```

## Common Patterns

### Testing Validations

```ruby
describe "validations" do
  it { should validate_presence_of(:name) }
  it { should validate_uniqueness_of(:email).case_insensitive }
  it { should validate_length_of(:name).is_at_most(255) }
end
```

### Testing Associations

```ruby
describe "associations" do
  it { should belong_to(:organization) }
  it { should have_many(:shows).dependent(:destroy) }
  it { should have_many(:users).through(:user_roles) }
end
```

### Testing Scopes

```ruby
describe "scopes" do
  describe ".active" do
    it "returns only active records" do
      active = create(:production, active: true)
      inactive = create(:production, active: false)
      
      expect(Production.active).to include(active)
      expect(Production.active).not_to include(inactive)
    end
  end
end
```

### Testing Callbacks

```ruby
describe "callbacks" do
  it "sets default values before validation" do
    production = build(:production, initials: nil)
    production.valid?
    expect(production.initials).to be_present
  end
end
```

### Testing Enums

```ruby
describe "status enum" do
  it "can be pending" do
    request = create(:audition_request, status: :pending)
    expect(request.pending?).to be true
  end

  it "can be approved" do
    request = create(:audition_request, status: :approved)
    expect(request.approved?).to be true
  end
end
```

## Troubleshooting

### System Tests Hanging

If system tests hang:
1. Check Chrome/Chromium is installed: `which google-chrome`
2. Increase wait time in `spec/support/capybara.rb`
3. Run with timeout: `timeout 60 bundle exec rspec spec/system/`

### Database Issues

If you see "database is locked" errors:
1. Make sure only one test run is active
2. Check `spec/support/database_cleaner.rb` configuration
3. System tests should use `strategy: :deletion`, not `:transaction`

### Factory Validation Errors

If factories fail to create records:
1. Check the model validations
2. Ensure required associations are defined in the factory
3. Use `build(:model)` in tests instead of `create` when possible

### Capybara Can't Find Elements

If Capybara can't find elements:
1. Use `save_screenshot` to debug: `save_screenshot('debug.png')`
2. Check that JavaScript has loaded: `expect(page).to have_content("Expected Text", wait: 10)`
3. Ensure the correct driver is used: System tests should use `:headless_chrome`

## Best Practices

1. **Keep tests focused**: One concept per test
2. **Use descriptive test names**: "it creates a user with valid attributes"
3. **Follow Arrange-Act-Assert pattern**:
   - Arrange: Set up test data
   - Act: Perform the action
   - Assert: Verify the result
4. **Don't test framework functionality**: Don't test that Rails associations work
5. **Test behavior, not implementation**: Test what, not how
6. **Use `let` for reusable test data**: But avoid overusing it
7. **Keep factories simple**: Add complexity in tests, not factories
8. **Write tests for bug fixes**: Prevent regressions
9. **Run tests frequently**: Catch issues early

## Continuous Integration

Tests run automatically on every PR via GitHub Actions. Make sure all tests pass locally before pushing:

```bash
# Run all tests
bundle exec rspec

# Check for issues
bundle exec rubocop
bundle exec brakeman
```

## Generating Test Templates

We provide a script to generate test templates for new models:

```bash
# Generate a test template for a model
ruby script/generate_test_template.rb ModelName

# Example:
ruby script/generate_test_template.rb EmailGroup
# Creates: spec/models/email_group_spec.rb
```

This creates a basic test structure with sections for:
- Validations
- Associations  
- Instance methods
- Class methods

Then customize the template based on your model's specific needs.

## Getting Help

- Check existing tests for examples: `spec/models/`, `spec/system/`
- Review RSpec documentation: https://rspec.info/
- Review Capybara documentation: https://rubydoc.info/github/teamcapybara/capybara
- Review FactoryBot documentation: https://github.com/thoughtbot/factory_bot

## Quick Reference

```bash
# Run tests
bundle exec rspec                          # All tests
bundle exec rspec spec/models/             # Model tests only
bundle exec rspec spec/models/user_spec.rb # Specific file
bundle exec rspec spec/models/user_spec.rb:10 # Specific test

# Generate test coverage report
bundle exec rspec --format documentation

# Run tests in parallel (if configured)
bundle exec parallel_rspec spec/
```
