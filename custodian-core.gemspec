# frozen_string_literal: true

require_relative "lib/custodian/core/version"

Gem::Specification.new do |spec|
  spec.name = "custodian-core"
  spec.version = Custodian::Core::VERSION
  spec.authors = ["lucasnshuntervoa"]
  spec.email = ["lucas.ns.software.engineer@gmail.com"]

  spec.summary = "A domain-agnostic chain-of-custody engine for Ruby."
  spec.description = "Custodian::Core implements a generic chain-of-custody mechanism over a " \
                     "tree of responsibilities. Concrete domains are implemented as satellite " \
                     "gems that register actions into this core via a registry."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # This gem is a Rails engine so that satellite gems can rely on it to ship
  # ActiveRecord models and migrations in later steps. We depend on the
  # specific Rails components isolate_namespace/ActiveRecord actually need
  # (actionpack for Rails::Engine's route set, activerecord for models)
  # rather than the "rails" umbrella gem, to avoid pulling in ActionMailer,
  # ActionCable, ActionText, ActiveStorage, ActionView, Nokogiri, etc. into a
  # domain-agnostic core (see docs/adr/0001-domain-agnostic-core.md).
  spec.add_dependency "actionpack", ">= 7.0"
  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "ancestry", ">= 4.0"
  spec.add_dependency "railties", ">= 7.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
