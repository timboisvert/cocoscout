# frozen_string_literal: true

# Audit log row for any change to a Mic — producer edit, accepted suggestion,
# admin override, migration wizard, system action.
class MicEdit < ApplicationRecord
  belongs_to :mic
  belongs_to :editor, class_name: "User",
                      foreign_key: :editor_user_id, optional: true

  enum :source, {
    producer: 0,
    suggestion: 1,
    admin: 2,
    migration: 3,
    system: 4
  }, prefix: :source
end
