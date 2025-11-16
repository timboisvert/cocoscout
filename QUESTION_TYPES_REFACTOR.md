# Question Types Refactoring - Developer Guide

## Overview
The question type system has been refactored from hardcoded if/elsif chains to a scalable, maintainable architecture using a registry pattern.

## Adding a New Question Type

To add a new question type, you only need to create **one new file**:

### Step 1: Create the Type Class

Create a new file in `app/models/question_types/`:

```ruby
# app/models/question_types/my_new_type.rb
module QuestionTypes
  class MyNewType < Base
    def self.key
      "my-new-type"  # The database value
    end

    def self.label
      "My New Type"  # The display label
    end

    def self.needs_options?
      false  # true if this type requires question_options
    end

    def self.parse_answer_value(value)
      # Transform the stored value for display
      # Return an array
      [value]
    end
  end
end

# Register the type
QuestionTypes::Base.register("my-new-type", QuestionTypes::MyNewType)
```

### Step 2: Create the Input Partial

Create a view partial for the input in `app/views/questions/input_types/`:

```erb
<%# app/views/questions/input_types/_my-new-type.html.erb %>
<%= text_field_tag "question[#{question.id}]", answer_value, 
    class: "block shadow-sm rounded-lg border px-3 py-2 mt-2 w-full",
    required: required %>
```

### Step 3: Create the Answer Display Partial

Create a view partial for displaying answers in `app/views/questions/answer_types/`:

```erb
<%# app/views/questions/answer_types/_my-new-type.html.erb %>
<%= answer.value %>
```

### That's it!

Your new question type is now:
- ✅ Available in the dropdown when creating questions
- ✅ Rendered correctly in all forms
- ✅ Displayed correctly in answer views
- ✅ Validated automatically
- ✅ Type-safe through the registry

## Migration from Old Code

### Before (Scattered Logic)
```ruby
# In 10+ different files:
if question.question_type == "text"
  # 5-10 lines of logic
elsif question.question_type == "textarea"
  # 5-10 lines of logic
elsif question.question_type == "yesno"
  # 5-10 lines of logic
# ... etc
end
```

### After (Centralized)
```ruby
# In views:
<%= render_question_input(question, @answers) %>
<%= render_question_answer(answer) %>

# In models:
question.question_type_class.label
question.question_type_class.needs_options?
question.question_type_class.parse_answer_value(value)

# In controllers:
if @question.question_type_class&.needs_options?
  # ...
end
```

## Key Classes

### QuestionTypes::Base
The base class that provides:
- `.registry` - Hash of all registered types
- `.all_types` - Array of all type classes (sorted by key)
- `.find(key)` - Find a type class by key
- `.register(key, klass)` - Register a new type

### Question Model
- `#question_type_class` - Returns the QuestionType class for this question

### QuestionsHelper
- `render_question_input(question, answers, options)` - Render input for a question
- `render_question_answer(answer)` - Render display for an answer

## Verification

Run the verification rake task to ensure all questions have valid types:

```bash
rails question_types:verify      # Verify all questions
rails question_types:list_types  # List all registered types
rails question_types:stats       # Show usage statistics
```

## Testing

Each question type should have a spec file in `spec/models/question_types/`:

```ruby
# spec/models/question_types/my_new_type_spec.rb
require 'rails_helper'

RSpec.describe QuestionTypes::MyNewType do
  describe '.key' do
    it 'returns the correct key' do
      expect(QuestionTypes::MyNewType.key).to eq('my-new-type')
    end
  end

  describe '.label' do
    it 'returns the correct label' do
      expect(QuestionTypes::MyNewType.label).to eq('My New Type')
    end
  end

  # Add more tests...
end
```

## Files Changed in This Refactor

**New Files (Core):**
- `app/models/question_types/base.rb`
- `app/models/question_types/text_type.rb`
- `app/models/question_types/textarea_type.rb`
- `app/models/question_types/yesno_type.rb`
- `app/models/question_types/multiple_multiple_type.rb`
- `app/models/question_types/multiple_single_type.rb`

**New Files (Views):**
- `app/views/questions/input_types/_*.html.erb` (5 files)
- `app/views/questions/answer_types/_*.html.erb` (5 files)
- `app/helpers/questions_helper.rb`

**Modified Files:**
- `app/models/question.rb`
- `app/models/answer.rb`
- `app/controllers/manage/audition_cycles_controller.rb`
- `app/views/manage/audition_cycles/_questions.html.erb`
- `app/views/manage/audition_cycles/preview.html.erb`
- `app/views/manage/audition_requests/edit_answers.html.erb`
- `app/views/manage/audition_requests/_answers.html.erb`
- `app/views/my/submit_audition_request/form.html.erb`

**Test Files:**
- `spec/models/question_types/*.rb` (6 new files)
- `spec/models/question_spec.rb` (enhanced)
- `spec/models/answer_spec.rb` (enhanced)

**Tools:**
- `lib/tasks/verify_question_types.rake`

## Benefits

1. **Scalability**: Add new types with one class file instead of touching 10+ files
2. **Maintainability**: All type logic in one place
3. **Testability**: Each type is independently testable
4. **DRY**: Eliminated ~200 lines of duplicated code
5. **Type Safety**: Registry prevents typos and invalid types
6. **Discoverability**: `QuestionTypes::Base.all_types` shows all available types
