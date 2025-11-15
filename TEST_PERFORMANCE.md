# Test Performance and Best Practices

This document provides guidance on writing performant tests and understanding the trade-offs between different test types.

## Test Performance Comparison

### Model Tests (Fastest)
- **Average time**: ~0.01 seconds per test
- **Total for 180 tests**: ~1.8 seconds
- **Use for**: Validations, associations, business logic, model methods

### Request Tests (Medium)
- **Average time**: ~0.05-0.1 seconds per test  
- **Use for**: API endpoints, controller actions, integration between components

### System Tests (Slowest)
- **Average time**: 30-60 seconds per test
- **Reason**: Browser startup, JavaScript execution, network requests
- **Use sparingly for**: Critical user flows, complex UI interactions

## Test Pyramid

Follow the test pyramid principle:

```
    /\     System Tests (Few)
   /  \    
  /____\   Request Tests (Some)
 /______\  
/__________\ Model Tests (Many)
```

### Guidelines

1. **Write many model tests** - They're fast and test core business logic
2. **Write some request tests** - They verify controller/integration behavior
3. **Write few system tests** - They're slow but verify complete user flows

## When to Write Each Test Type

### Write Model Tests When:
- Testing validations
- Testing associations
- Testing instance or class methods
- Testing scopes or callbacks
- Testing model business logic
- You need fast feedback during development

### Write Request Tests When:
- Testing controller actions
- Testing API endpoints
- Testing redirects and responses
- Testing authentication/authorization
- Testing integration between models and controllers

### Write System Tests When:
- Testing complete user workflows
- Testing JavaScript interactions
- Testing form submissions with multiple steps
- Testing navigation between pages
- Verifying the user experience end-to-end

## System Test Performance Tips

Since system tests are slow, here are ways to optimize them:

### 1. Minimize System Tests
Only write system tests for critical flows:
- User authentication/registration
- Critical business transactions
- Complex multi-step forms
- Features with significant JavaScript

### 2. Use Factories Efficiently
```ruby
# Bad - Creates unnecessary records
let!(:user) { create(:user) }
let!(:organization) { create(:organization) }
let!(:production) { create(:production) }

# Better - Only create what you need
let(:user) { build(:user) }  # Use build when possible
let!(:organization) { create(:organization) }  # Only create when needed
```

### 3. Avoid Redundant System Tests
Don't write system tests for things already covered by model/request tests:

```ruby
# Bad - System test for simple validation
it "shows error for invalid email" do
  sign_in_as(user)
  visit edit_profile_path
  fill_in "email", with: "invalid"
  click_button "Save"
  expect(page).to have_content("Email is invalid")
end

# Good - Model test is sufficient
it "validates email format" do
  user = build(:user, email: "invalid")
  expect(user).not_to be_valid
  expect(user.errors[:email]).to include("is invalid")
end
```

### 4. Batch System Tests
Group related assertions in one test instead of multiple tests:

```ruby
# Less efficient - 3 separate tests (90-180 seconds)
it "shows user name" do
  sign_in_as(user)
  expect(page).to have_content(user.name)
end

it "shows user email" do
  sign_in_as(user)
  expect(page).to have_content(user.email)
end

it "has edit button" do
  sign_in_as(user)
  expect(page).to have_button("Edit Profile")
end

# More efficient - 1 test (30-60 seconds)
it "displays profile information with edit option" do
  sign_in_as(user)
  expect(page).to have_content(user.name)
  expect(page).to have_content(user.email)
  expect(page).to have_button("Edit Profile")
end
```

### 5. Use Request Tests for API-like Actions
If you're testing actions that don't require a browser:

```ruby
# Slow - System test (30-60 seconds)
it "creates a production" do
  sign_in_as(user)
  visit new_production_path
  fill_in "Name", with: "New Production"
  click_button "Create"
  expect(page).to have_content("Production created")
end

# Fast - Request test (0.1 seconds)
it "creates a production" do
  post productions_path, params: { production: { name: "New Production" } }
  expect(response).to redirect_to(production_path(Production.last))
  expect(Production.last.name).to eq("New Production")
end
```

## Development Workflow

### During Active Development
```bash
# Use model tests for fast feedback
bundle exec rspec spec/models/

# Use guard or similar for continuous testing
bundle exec guard
```

### Before Committing
```bash
# Run all fast tests
bundle exec rspec spec/models/ spec/requests/

# Run critical system tests only
bundle exec rspec spec/system/user_authentication_spec.rb
```

### In CI/CD
```bash
# Run all tests
bundle exec rspec

# Consider running system tests in parallel if possible
```

## Debugging Slow Tests

If tests are slower than expected:

### 1. Profile Your Tests
```bash
# Use --profile flag to see slowest tests
bundle exec rspec --profile 10
```

### 2. Check Database Queries
```ruby
# In spec_helper or rails_helper
config.before(:each) do
  ActiveRecord::Base.logger = Logger.new(STDOUT) if ENV['VERBOSE']
end

# Run with VERBOSE=1 to see queries
VERBOSE=1 bundle exec rspec spec/models/user_spec.rb
```

### 3. Identify N+1 Queries
Use bullet gem in test environment:

```ruby
# Gemfile
group :test do
  gem 'bullet'
end

# spec/rails_helper.rb
if Bullet.enable?
  config.before(:each) do
    Bullet.start_request
  end

  config.after(:each) do
    Bullet.perform_out_of_channel_notifications if Bullet.notification?
    Bullet.end_request
  end
end
```

## Common Anti-Patterns

### 1. Over-testing
```ruby
# Bad - Testing Rails functionality
it "has many productions" do
  expect(organization.productions).to be_a(ActiveRecord::Associations::CollectionProxy)
end

# Good - Testing your business logic
it "returns active productions only" do
  active = create(:production, organization: organization, active: true)
  inactive = create(:production, organization: organization, active: false)
  expect(organization.active_productions).to eq([active])
end
```

### 2. Testing Implementation Instead of Behavior
```ruby
# Bad - Tests implementation
it "calls Production.create" do
  expect(Production).to receive(:create)
  post productions_path, params: { production: attributes }
end

# Good - Tests behavior
it "creates a new production" do
  expect {
    post productions_path, params: { production: attributes }
  }.to change(Production, :count).by(1)
end
```

### 3. Brittle System Tests
```ruby
# Bad - Depends on exact UI text
expect(page).to have_content("Welcome to CocoScout! Click here to get started")

# Good - Tests essential functionality
expect(page).to have_content("Welcome")
expect(page).to have_link("Get Started")
```

## Continuous Improvement

As you add features:

1. **Always start with model tests** - They're fast and test core logic
2. **Add request tests for new endpoints** - Verify integration works
3. **Only add system tests for critical paths** - Where full UI interaction matters
4. **Review test suite periodically** - Remove redundant tests
5. **Monitor test times** - Keep total suite under 5 minutes when possible

## Resources

- [RSpec Best Practices](https://rspec.info/documentation/)
- [Testing Rails Applications](https://guides.rubyonrails.org/testing.html)
- [Better Specs](https://www.betterspecs.org/)
- [Effective Testing with RSpec 3](https://pragprog.com/titles/rspec3/effective-testing-with-rspec-3/)
