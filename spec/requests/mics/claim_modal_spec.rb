# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mics detail — claim listing modal", type: :request do
  let(:mic) { create(:mic) }

  it "renders the renamed trigger and the claim modal on an unclaimed mic" do
    get mics_detail_path(mic.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Claim this mic listing")
    expect(response.body).to include('id="claim-mic-modal"')
    # Ownership-clarifying copy is present.
    expect(response.body).to include("own and manage this listing's data")
  end
end
