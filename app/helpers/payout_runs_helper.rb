# frozen_string_literal: true

module PayoutRunsHelper
  # Where "the payout run" lives for this org: the one run in Money for a Pro
  # org (or the run list when nothing's open), the free Courses payout page
  # otherwise. One place per org, never two.
  def payout_run_home_path(organization = Current.organization)
    return manage_course_payout_run_path unless organization&.feature_available?(:money)

    run = PayoutBatch.current_open_draft(organization)
    run ? manage_payout_batch_path(run) : manage_payout_batches_path
  end
end
