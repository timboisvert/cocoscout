# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShortKeyService do
  describe ".generate" do
    it "generates a 5-character uppercase alphanumeric key for auditions" do
      key = described_class.generate(type: :audition)
      expect(key).to match(/\A[A-Z0-9]{5}\z/)
    end

    it "generates a 5-character uppercase alphanumeric key for signups" do
      key = described_class.generate(type: :signup)
      expect(key).to match(/\A[A-Z0-9]{5}\z/)
    end

    it "generates unique keys" do
      keys = 10.times.map { described_class.generate(type: :signup) }
      expect(keys.uniq.size).to eq(10)
    end

    it "raises error for invalid type" do
      expect { described_class.generate(type: :invalid) }
        .to raise_error(ArgumentError, /Invalid key type/)
    end

    it "supports custom key length" do
      key = described_class.generate(type: :signup, length: 8)
      expect(key.length).to eq(8)
    end
  end

  describe ".generate_for!" do
    it "assigns a key to a sign-up form" do
      form = create(:sign_up_form, short_code: nil)
      expect(form.short_code).to be_nil

      key = described_class.generate_for!(form, type: :signup)

      expect(key).to match(/\A[A-Z0-9]{5}\z/)
      expect(form.reload.short_code).to eq(key)
    end

    it "does not regenerate if key already present" do
      form = create(:sign_up_form, short_code: "EXIST")

      key = described_class.generate_for!(form, type: :signup)

      expect(key).to eq("EXIST")
      expect(form.reload.short_code).to eq("EXIST")
    end
  end

  describe ".find_by_key" do
    it "finds a sign-up form by short_code" do
      form = create(:sign_up_form, short_code: "ABCDE")

      result = described_class.find_by_key(type: :signup, key: "ABCDE")

      expect(result).to eq(form)
    end

    it "finds an audition cycle by token" do
      cycle = create(:audition_cycle, token: "FGHIJ")

      result = described_class.find_by_key(type: :audition, key: "FGHIJ")

      expect(result).to eq(cycle)
    end

    it "handles case-insensitive lookups" do
      form = create(:sign_up_form, short_code: "ABCDE")

      result = described_class.find_by_key(type: :signup, key: "abcde")

      expect(result).to eq(form)
    end

    it "returns nil for non-existent key" do
      result = described_class.find_by_key(type: :signup, key: "ZZZZZ")

      expect(result).to be_nil
    end
  end

  describe ".statistics" do
    it "returns statistics for all key types" do
      create(:sign_up_form, short_code: "KEY01")
      create(:sign_up_form, short_code: "KEY02")
      create(:audition_cycle, token: "TOK01")

      stats = described_class.statistics

      expect(stats[:signup][:used]).to be >= 2
      expect(stats[:audition][:used]).to be >= 1
      expect(stats[:signup][:total_capacity]).to eq(36**5)
      expect(stats[:combined][:total_used]).to eq(stats[:audition][:used] + stats[:signup][:used])
    end

    it "includes capacity information" do
      stats = described_class.statistics

      expect(stats[:signup][:key_length]).to eq(5)
      expect(stats[:signup][:charset_size]).to eq(36)
      expect(stats[:signup][:path_prefix]).to eq("/s/")
      expect(stats[:audition][:path_prefix]).to eq("/a/")
    end
  end

  describe ".all_keys" do
    it "returns all keys with associated information" do
      production = create(:production)
      form = create(:sign_up_form, short_code: "FORM1", production: production)
      cycle = create(:audition_cycle, token: "CYCL1", production: production)

      keys = described_class.all_keys

      form_key = keys.find { |k| k[:key] == "FORM1" }
      cycle_key = keys.find { |k| k[:key] == "CYCL1" }

      expect(form_key).to be_present
      expect(form_key[:type]).to eq(:signup)
      expect(form_key[:path]).to eq("/s/FORM1")
      expect(form_key[:production_name]).to eq(production.name)

      expect(cycle_key).to be_present
      expect(cycle_key[:type]).to eq(:audition)
      expect(cycle_key[:path]).to eq("/a/CYCL1")
      expect(cycle_key[:production_name]).to eq(production.name)
    end

    it "filters by type" do
      create(:sign_up_form, short_code: "FORM2")
      create(:audition_cycle, token: "CYCL2")

      signup_keys = described_class.all_keys(type: :signup)
      audition_keys = described_class.all_keys(type: :audition)

      expect(signup_keys.all? { |k| k[:type] == :signup }).to be true
      expect(audition_keys.all? { |k| k[:type] == :audition }).to be true
    end
  end

  describe ".health_check" do
    it "returns healthy status when capacity is low" do
      health = described_class.health_check

      expect(health[:healthy]).to be true
      expect(health[:warnings]).to be_empty
    end
  end

  describe ".capacity_for_length" do
    it "calculates capacity correctly" do
      expect(described_class.capacity_for_length(5)).to eq(36**5)
      expect(described_class.capacity_for_length(6)).to eq(36**6)
      expect(described_class.capacity_for_length(3)).to eq(36**3)
    end
  end
end
