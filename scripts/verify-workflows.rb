#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"

ROOT = File.expand_path("..", __dir__)
WORKFLOWS = Dir[File.join(ROOT, ".github", "workflows", "*.yml")].sort.freeze

def fail_check(message)
  warn "ERROR: #{message}"
  exit 1
end

def exact_permissions(document, expected, path)
  actual = document.fetch("permissions", {})
  fail_check("#{path} permissions differ: #{actual.inspect}") unless actual == expected
end

documents = {}
WORKFLOWS.each do |path|
  document = YAML.safe_load(File.read(path), aliases: true)
  documents[File.basename(path)] = document

  document.fetch("jobs", {}).each_value do |job|
    job.fetch("steps", []).each do |step|
      if step["uses"]
        reference = step.fetch("uses")
        unless reference.match?(%r{\Aactions/[^@]+@[0-9a-f]{40}\z})
          fail_check("external action is not pinned to a full SHA: #{reference}")
        end
      end

      next unless step["run"]

      _stdout, stderr, status = Open3.capture3("bash", "-n", "-c", step.fetch("run"))
      fail_check("bash syntax failed in #{path} step #{step['name']}: #{stderr}") unless status.success?
    end
  end
end

exact_permissions(
  documents.fetch("verify-web.yml"),
  { "contents" => "read" },
  "verify-web.yml"
)
exact_permissions(
  documents.fetch("merge-guard.yml"),
  { "contents" => "write", "pull-requests" => "write" },
  "merge-guard.yml"
)
exact_permissions(
  documents.fetch("deploy-pages.yml"),
  {
    "contents" => "read",
    "actions" => "read",
    "pages" => "write",
    "id-token" => "write"
  },
  "deploy-pages.yml"
)

guard = File.read(File.join(ROOT, ".github", "workflows", "merge-guard.yml"))
deploy = File.read(File.join(ROOT, ".github", "workflows", "deploy-pages.yml"))

fail_check("Merge Guard must not check out code") if guard.include?("actions/checkout")
%w[previous_filename HEAD_REPO EXPECTED_FILES pull_request_target].each do |marker|
  fail_check("Merge Guard is missing #{marker}") unless guard.include?(marker)
end

[
  "workflow_dispatch",
  "workflow_run.id",
  "workflow_run.pull_requests",
  "github-actions[bot]",
  "head_tree",
  "merge_tree",
  "for attempt in {1..60}",
  "::warning::",
  "steps.authorize.outputs.run_id",
  "Confirm main is still current"
].each do |marker|
  fail_check("Deploy Pages is missing #{marker}") unless deploy.include?(marker)
end

puts "workflow verification passed"
