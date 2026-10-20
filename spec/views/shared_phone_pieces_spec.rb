# frozen_string_literal: true

require "rails_helper"

# The shared phone pieces (V1.1 plan Phase 0b): the sheet, the ⋯ menu and
# the Save bar.
RSpec.describe "Shared phone pieces", type: :view do
  def html(...) = Nokogiri::HTML.fragment(render(...))

  it "draws a sheet: a bottom sheet on a phone, a modal from sm up, with the pink header and a stacked footer" do
    view.lookup_context.prefixes << "shared"
    doc = html(layout: "shared/sheet", locals: { id: "edit-show", title: "Edit show", footer: "<a href='#'>Save</a>".html_safe }) { "Body words" }
    sheet = doc.at_css("#edit-show")
    expect(sheet["class"]).to include("hidden", "items-end", "sm:items-center")
    expect(sheet["data-controller"]).to eq("modal")
    expect(doc.at_css("h3").text).to eq("Edit show")
    expect(doc.at_css(".from-pink-500")).to be_present
    expect(doc.text).to include("Body words", "Save")
  end

  it "draws a ⋯ menu: a dropdown and the same items in a phone sheet, posting non-GET items" do
    items = [ { text: "Edit", path: "/shows/1/edit" }, { text: "Duplicate", path: "/shows/1/duplicate", method: :post } ]
    doc = html(partial: "shared/action_menu", locals: { id: "show-1-actions", items: items })
    expect(doc.at_css('[data-dropdown-target="menu"]').css("a, button").map(&:text).map(&:squish)).to eq(%w[Edit Duplicate])
    expect(doc.at_css("#show-1-actions-sheet")).to be_present
    expect(doc.css("form[action='/shows/1/duplicate']").size).to eq(2)
    expect(doc.to_html).not_to match(/bg-red|text-red/)
  end

  it "draws nothing for a ⋯ menu with no items" do
    expect(render(partial: "shared/action_menu", locals: { id: "empty", items: [] }).to_s.strip).to be_empty
  end

  it "pins the Save bar to the bottom on a phone and leaves it in the form from sm up" do
    allow(view).to receive(:turbo_native_app?).and_return(false)
    doc = html(layout: "shared/sticky_actions") { "<button>Save</button>".html_safe }
    bar = doc.at_css("[data-sticky-actions]")
    expect(bar["class"]).to include("fixed", "bottom-0", "sm:static")
    expect(bar.text).to include("Save")
  end

  it "leaves room for the Coco button in the app" do
    allow(view).to receive(:turbo_native_app?).and_return(true)
    expect(html(layout: "shared/sticky_actions") { "x" }.at_css("[data-sticky-actions]")["class"]).to include("pr-[96px]")
  end
end
