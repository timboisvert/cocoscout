# frozen_string_literal: true

# Per-user, per-production scratchpad for the audition cycle wizard.
# Stored in the database because the wizard state easily exceeds the
# 4 KB session cookie limit (especially the audition_sessions list).
class AuditionWizardState < ApplicationRecord
  belongs_to :production
  belongs_to :user
end
