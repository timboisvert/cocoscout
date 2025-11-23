class ProfileSkillsService
  class << self
    def all_categories
      skills_config.keys.map(&:to_s).sort
    end

    def skills_for_category(category)
      skills_config[category.to_sym] || []
    end

    def all_skills
      skills_config.values.flatten.sort
    end

    def valid_skill?(category, skill_name)
      skills_for_category(category).include?(skill_name)
    end

    def suggested_sections
      [
        "Theatre",
        "Musical Theatre",
        "Film",
        "Television",
        "Web Series",
        "Commercials",
        "Voice-Over",
        "Stand-Up Comedy",
        "Improv",
        "Sketch Comedy",
        "Dance",
        "Music/Concerts",
        "Magic",
        "Circus Arts",
        "Burlesque",
        "Cabaret",
        "Industrial/Corporate",
        "Motion Capture",
        "New Media"
      ]
    end

    def category_display_name(category)
      category.to_s.titleize.gsub("_", " / ")
    end

    private

    def skills_config
      @skills_config ||= YAML.load_file(Rails.root.join("config", "profile_skills.yml")).deep_symbolize_keys
    end
  end
end
