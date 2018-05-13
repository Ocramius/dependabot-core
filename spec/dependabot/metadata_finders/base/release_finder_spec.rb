# frozen_string_literal: true

require "octokit"
require "gitlab"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/source"
require "dependabot/metadata_finders/base/release_finder"

RSpec.describe Dependabot::MetadataFinders::Base::ReleaseFinder do
  subject(:finder) do
    described_class.new(
      source: source,
      dependency: dependency,
      credentials: credentials
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [
        { file: "Gemfile", requirement: ">= 0", groups: [], source: nil }
      ],
      previous_version: dependency_previous_version,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_previous_version) { "1.0.0" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/#{dependency_name}"
    )
  end

  describe "#releases_url" do
    subject { finder.releases_url }

    context "with a github repo" do
      it "gets the right URL" do
        expect(subject).to eq("https://github.com/gocardless/business/releases")
      end
    end

    context "with a gitlab source" do
      let(:source) do
        Dependabot::Source.new(
          provider: "gitlab",
          repo: "org/#{dependency_name}"
        )
      end

      it "gets the right URL" do
        expect(subject).to eq("https://gitlab.com/org/business/tags")
      end
    end

    context "without a source" do
      let(:source) { nil }
      it { is_expected.to be_nil }
    end
  end

  describe "#releases_text" do
    subject { finder.releases_text }

    context "with a github repo" do
      let(:github_url) do
        "https://api.github.com/repos/gocardless/business/releases"
      end

      let(:github_status) { 200 }

      before do
        stub_request(:get, github_url).
          with(headers: { "Authorization" => "token token" }).
          to_return(status: github_status,
                    body: github_response,
                    headers: { "Content-Type" => "application/json" })
      end

      context "with releases" do
        let(:github_response) { fixture("github", "business_releases.json") }

        context "when the release is present" do
          let(:dependency_version) { "1.8.0" }

          context "and is updating from one version previous" do
            let(:dependency_previous_version) { "1.7.0" }

            it "gets the right text" do
              expect(subject).
                to eq(
                  "## v1.8.0\n"\
                  "- Add 2018-2027 TARGET holiday defintions\n"\
                  "- Add 2018-2027 Bankgirot holiday defintions"
                )
            end

            it "caches the call to GitHub" do
              finder.releases_text
              finder.releases_text
              expect(WebMock).to have_requested(:get, github_url).once
            end

            context "but prefixed" do
              let(:github_response) do
                fixture("github", "prefixed_releases.json")
              end

              it "still gets the right text" do
                expect(subject).
                  to eq(
                    "## business-1.8.0\n"\
                    "- Add 2018-2027 TARGET holiday defintions\n"\
                    "- Add 2018-2027 Bankgirot holiday defintions"
                  )
              end
            end

            context "but is blank" do
              let(:dependency_version) { "1.7.0" }
              let(:dependency_previous_version) { "1.7.0.beta" }

              it { is_expected.to be_nil }
            end

            context "but is nil" do
              let(:dependency_version) { "1.7.0.beta" }
              let(:dependency_previous_version) { "1.7.0.alpha" }

              it { is_expected.to be_nil }
            end

            context "but has blank names" do
              let(:github_response) do
                fixture("github", "releases_no_names.json")
              end

              it "falls back to the tag name" do
                expect(subject).
                  to eq(
                    "## v1.8.0\n"\
                    "- Add 2018-2027 TARGET holiday defintions\n"\
                    "- Add 2018-2027 Bankgirot holiday defintions"
                  )
              end
            end

            context "but has tag names with dashes, and it's Java" do
              let(:github_response) do
                fixture("github", "releases_dash_tags.json")
              end
              let(:dependency_version) { "6.5.1" }
              let(:dependency_previous_version) { "6.4.0" }

              it "falls back to the tag name" do
                expect(subject).
                  to eq(
                    "## JasperReports 6.5.1\n"\
                    "Body for 6.5.1\n"\
                    "\n"\
                    "## JasperReports 6.5.0\n"\
                    "Body for 6.5.0\n"\
                    "\n"\
                    "## JasperReports 6.4.3\n"\
                    "Body for 6.4.3\n"\
                    "\n"\
                    "## JasperReports 6.4.1\n"\
                    "Body for 6.4.1"
                  )
              end
            end
          end

          context "and is updating from several versions previous" do
            let(:dependency_previous_version) { "1.6.0" }

            it "gets the right text" do
              expect(subject).
                to eq(
                  "## v1.8.0\n"\
                  "- Add 2018-2027 TARGET holiday defintions\n"\
                  "- Add 2018-2027 Bankgirot holiday defintions\n"\
                  "\n"\
                  "## v1.7.0\n"\
                  "No release notes provided.\n"\
                  "\n"\
                  "## v1.7.0.beta\n"\
                  "No release notes provided.\n"\
                  "\n"\
                  "## v1.7.0.alpha\n"\
                  "No release notes provided."
                )
            end

            context "but all versions are blank or nil" do
              let(:dependency_version) { "1.7.0" }
              it { is_expected.to be_nil }
            end

            context "when the latest version is blank, but not all are" do
              let(:dependency_version) { "1.7.0" }
              let(:dependency_previous_version) { "1.5.0" }

              it "gets the right text" do
                expect(subject).
                  to eq(
                    "## v1.7.0\n"\
                    "No release notes provided.\n"\
                    "\n"\
                    "## v1.7.0.beta\n"\
                    "No release notes provided.\n"\
                    "\n"\
                    "## v1.7.0.alpha\n"\
                    "No release notes provided.\n"\
                    "\n"\
                    "## v1.6.0\n"\
                    "Mad props to @greysteil for the @angular/scope work"
                  )
              end
            end
          end

          context "and the previous release doesn't have a github release" do
            let(:dependency_previous_version) { "1.5.1" }

            it "uses the version number to filter the releases" do
              expect(subject).
                to eq(
                  "## v1.8.0\n"\
                  "- Add 2018-2027 TARGET holiday defintions\n"\
                  "- Add 2018-2027 Bankgirot holiday defintions\n"\
                  "\n"\
                  "## v1.7.0\n"\
                  "No release notes provided.\n"\
                  "\n"\
                  "## v1.7.0.beta\n"\
                  "No release notes provided.\n"\
                  "\n"\
                  "## v1.7.0.alpha\n"\
                  "No release notes provided.\n"\
                  "\n"\
                  "## v1.6.0\n"\
                  "Mad props to @greysteil for the @angular/scope work"
                )
            end
          end
        end

        context "when the release is not present" do
          let(:dependency_version) { "1.9.0" }
          let(:dependency_previous_version) { "1.8.0" }
          it { is_expected.to be_nil }

          context "and there is a blank named release that needs excluding" do
            let(:github_response) do
              fixture("github", "releases_ember_cp.json")
            end
            let(:dependency_version) { "3.5.3" }
            let(:dependency_previous_version) { "3.5.2" }
            it { is_expected.to be_nil }
          end
        end

        context "when the release has a bad name" do
          let(:dependency_version) { "1.8.0" }
          let(:dependency_previous_version) { "1.7.0" }
          let(:github_response) do
            fixture("github", "business_releases_bad_name.json")
          end
          it "gets the right text" do
            expect(subject).
              to eq(
                "## v1.7.0\n"\
                "- Add 2018-2027 TARGET holiday defintions\n"\
                "- Add 2018-2027 Bankgirot holiday defintions"
              )
          end
        end
      end
    end

    context "with a gitlab source" do
      let(:gitlab_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tags"
      end
      let(:source) do
        Dependabot::Source.new(
          provider: "gitlab",
          repo: "org/#{dependency_name}"
        )
      end

      let(:gitlab_response) { fixture("gitlab", "business_tags.json") }

      before do
        stub_request(:get, gitlab_url).
          to_return(status: 200,
                    body: gitlab_response,
                    headers: { "Content-Type" => "application/json" })
      end

      let(:dependency_version) { "1.4.0" }
      let(:dependency_previous_version) { "1.3.0" }

      it "gets the right text" do
        expect(subject).
          to eq(
            "## v1.4.0\n"\
            "Some release notes"
          )
      end
    end

    context "without a recognised source" do
      let(:source) { nil }
      it { is_expected.to be_nil }
    end
  end
end
