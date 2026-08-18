# frozen_string_literal: true

require_relative "lib/custodian/core/version"

Gem::Specification.new do |spec|
  spec.name = "custodian-core"
  spec.version = Custodian::Core::VERSION
  spec.authors = ["Lucas nunes de sousa"]
  spec.email = ["lucas.ns.software.engineer@gmail.com"]
  spec.homepage = "https://github.com/lucasnssoftwareengineer-alt/custodian-core"
  spec.metadata["source_code_uri"] = "https://github.com/lucasnssoftwareengineer-alt/custodian-core"
  spec.metadata["changelog_uri"] = "https://github.com/lucasnssoftwareengineer-alt/custodian-core/blob/main/CHANGELOG.md"
  spec.summary = "A domain-agnostic chain-of-custody engine for Ruby."
  spec.description = "Custodian::Core resolves a chain of custody over a tree of responsibilities: " \
                     "it identifies the next responsible party and demands the action a previous " \
                     "ward could not fulfill, climbing the tree until someone can act. It carries " \
                     "no business rules from any specific domain - concrete domains are implemented " \
                     "as satellite gems that register actions into this core via a registry."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["rubygems_mfa_required"] = "true"

  # Keep the package independent from Git and deliberately limited to files
  # useful to consumers. Development configuration, specs, CI, and internal
  # architecture records remain in the repository but not in the gem.
  spec.files = Dir.chdir(__dir__) do
    %w[CHANGELOG.md LICENSE.txt README.md custodian-core.gemspec] +
      Dir.glob(%w[app/**/*.rb db/**/*.rb lib/**/*.rb sig/**/*.rbs])
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
  spec.add_dependency "actionpack", ">= 7.0", "< 9.0"
  spec.add_dependency "activerecord", ">= 7.0", "< 9.0"
  spec.add_dependency "activesupport", ">= 7.0", "< 9.0"
  spec.add_dependency "ancestry", ">= 4.0", "< 6.0"
  spec.add_dependency "railties", ">= 7.0", "< 9.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
