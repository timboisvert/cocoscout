# frozen_string_literal: true

# Concern for detecting and handling suspicious/malicious input patterns
# Used to prevent injection attacks (XSS, JNDI, path traversal, etc.)
module SuspiciousDetection
  extend ActiveSupport::Concern

  # Characters that indicate injection attacks or are simply invalid for names
  MALICIOUS_PATTERNS = [
    /[\x00-\x1f\x7f]/, # Control characters
    /[<>]/, # HTML/XML injection
    /[|&;`$(){}\[\]]/, # Shell injection
    /\$\{/,                                      # Template injection (Log4j, etc.)
    /-->/,                                       # HTML comment injection
    %r{\*/},                                     # Comment close injection
    %r{/>},                                      # Self-closing tag injection
    /%[0-9a-f]{2}/i,                             # URL encoded characters
    /\\x[0-9a-f]{2}/i,                           # Hex escape sequences
    %r{\.\.[\\/]},                               # Path traversal
    %r{/(etc|bin|usr|var|tmp)/}i,                # Unix path injection
    /[a-z]:\\|%systemroot%/i,                    # Windows path injection
    /\b(passwd|boot\.ini|win\.ini)\b/i,          # Sensitive file names
    /\b(exec|eval|system|popen|spawn)\b/i,       # Code execution keywords
    /(wget|curl|bash|sh|cat|type)\s/i,           # Command execution
    /jndi:|ldap:|rmi:/i,                         # JNDI injection (Log4j)
    %r{file://}i # File protocol
  ].freeze

  # SQL patterns for finding suspicious records in the database
  SUSPICIOUS_SQL_PATTERNS = [
    "name LIKE '%<%'",
    "name LIKE '%>%'",
    "name LIKE '%|%'",
    "name LIKE '%$%'",
    "name LIKE '%../%'",
    "name LIKE '%etc/passwd%'",
    "name LIKE '%jndi:%'",
    "name LIKE '%ldap:%'",
    "name LIKE '%/>%'",
    "name LIKE '%--%'",
    "name LIKE '%{%'",
    "name LIKE '%}%'",
    "name LIKE '%`%'",
    "name LIKE '%[%'",
    "name LIKE '%]%'",
    "name LIKE '%/bin/%'",
    "name LIKE '%/usr/%'",
    "name LIKE '%exec(%'",
    "name LIKE '%file://%'",
    "name LIKE '%\\x%'",
    "name LIKE '%\\\\%'",
    "email LIKE '%<%'",
    "email LIKE '%>%'",
    "email LIKE '%jndi:%'"
  ].freeze

  included do
    validate :name_not_malicious
    validate :email_not_malicious
    before_validation :sanitize_name
  end

  class_methods do
    def suspicious
      where(SUSPICIOUS_SQL_PATTERNS.join(" OR "))
    end

    def name_looks_suspicious?(name)
      return false if name.blank?

      MALICIOUS_PATTERNS.any? { |pattern| name.match?(pattern) }
    end

    def cleanup_suspicious!(dry_run: true)
      suspicious_records = suspicious.includes(:user)
      count = suspicious_records.count

      if dry_run
        puts "Found #{count} suspicious records (dry run, not deleting):"
        suspicious_records.find_each do |person|
          puts "  ID: #{person.id}, Name: #{person.name.inspect}, Email: #{person.email}"
        end
      else
        puts "Deleting #{count} suspicious records..."
        suspicious_records.find_each do |person|
          puts "  Deleting ID: #{person.id}, Name: #{person.name.inspect}"
          person.destroy
        end
        puts "Deleted #{count} suspicious records."
      end
      count
    end
  end

  private

  def name_not_malicious
    return if name.blank?

    MALICIOUS_PATTERNS.each do |pattern|
      if name.match?(pattern)
        errors.add(:name, "contains invalid characters or patterns")
        return
      end
    end
  end

  def email_not_malicious
    return if email.blank?

    MALICIOUS_PATTERNS.each do |pattern|
      if email.match?(pattern)
        errors.add(:email, "contains invalid characters or patterns")
        return
      end
    end
  end

  def sanitize_name
    return if name.blank?

    # Strip leading/trailing whitespace
    self.name = name.strip

    # Collapse multiple spaces into one
    self.name = name.gsub(/\s+/, " ")

    # Remove any null bytes
    self.name = name.delete("\x00")
  end
end
