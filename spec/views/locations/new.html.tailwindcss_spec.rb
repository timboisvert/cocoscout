require 'rails_helper'

RSpec.describe "locations/new", type: :view do
  before(:each) do
    assign(:location, Location.new(
      address1: "MyString",
      address2: "MyString",
      city: "MyString",
      state: "MyString",
      postal_code: "MyString"
    ))
  end

  it "renders new location form" do
    render

    assert_select "form[action=?][method=?]", locations_path, "post" do

      assert_select "input[name=?]", "location[address1]"

      assert_select "input[name=?]", "location[address2]"

      assert_select "input[name=?]", "location[city]"

      assert_select "input[name=?]", "location[state]"

      assert_select "input[name=?]", "location[postal_code]"
    end
  end
end
