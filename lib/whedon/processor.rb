require_relative 'github'
require 'yaml'
require 'securerandom'

module Whedon
  class Processor
    include GitHub

    attr_accessor :review_issue_id
    attr_accessor :review_body
    attr_accessor :repository_address
    attr_accessor :archive_doi
    attr_accessor :paper_path
    attr_accessor :xml_path
    attr_accessor :doi_batch_id
    attr_accessor :paper

    def initialize(review_issue_id, review_body)
      @review_issue_id = review_issue_id
      @review_body = review_body
      @repository_address = review_body[REPO_REGEX]
      @archive_doi = review_body[ARCHIVE_REGEX]
    end

    def set_paper(path)
      @paper = Whedon::Paper.new(review_issue_id, path)
    end

    # Clone the repository... (assumes it's git)
    def clone
      repository_address = review_body[REPO_REGEX]

      # Skip if the repo has already been cloned
      if File.exists?("tmp/#{review_issue_id}/.git")
        puts "Looks like Git repo already exists at tmp/#{review_issue_id}"
        return
      end

      # First make the folder
      FileUtils::mkdir_p("tmp/#{review_issue_id}")

      # Then clone the repository
      `git clone #{repository_address} tmp/#{review_issue_id}`
    end

    # Find possible papers to be compiled
    def find_paper_paths
      paper_paths = []
      Find.find("tmp/#{review_issue_id}") do |path|
        paper_paths << path if path =~ /paper\.md$/
      end

      return paper_paths
    end

    # Find possible papers to be compiled
    def find_bib_path
      bib_paths = []
      Find.find("tmp/#{review_issue_id}") do |path|
        bib_paths << path if path =~ /.bib$/
      end

      return bib_paths
    end

    # Find XML paper
    def find_xml_paths
      xml_paths = []
      Find.find("tmp/#{review_issue_id}") do |path|
        xml_paths << path if path =~ /paper\.xml$/
      end

      return xml_paths
    end

    # Upload docs to joss-papers repo
    def upload_pdfs

    end

    # Try and compile the paper target
    def compile
      generate_pdf
      generate_xml
      generate_html
      generate_crossref
    end

    def generate_pdf(paper_issue=nil, paper_volume=nil, paper_year=nil)
      latex_template_path = "#{Dir.pwd}/resources/latex.template"

      # TODO: Sanitize all the things!
      paper_title = paper.title.gsub!('_', '\_')
      paper_year ||= Time.now.strftime('%Y')
      paper_issue ||= CURRENT_ISSUE
      paper_volume ||= CURRENT_VOLUME

      # TODO: may eventually want to swap out the latex template
      `cd #{paper.directory} && pandoc \
      -V repository="#{repository_address}" \
      -V archive_doi="#{archive_doi}" \
      -V paper_url="#{paper.pdf_url}" \
      -V formatted_doi="#{paper.formatted_doi}" \
      -V review_issue_url="#{paper.review_issue_url}" \
      -V graphics="true" \
      -V issue="#{paper_issue}" \
      -V volume="#{paper_volume}" \
      -V page="#{paper.review_issue_id}" \
      -V joss_logo_path="#{Dir.pwd}/resources/joss-logo.png" \
      -V year="#{paper_year}" \
      -V formatted_doi="#{paper.formatted_doi}" \
      -V citation_author="#{paper.citation_author}" \
      -V paper_title="#{paper.title}" \
      -S -o #{paper.filename_doi}.pdf -V geometry:margin=1in \
      --latex-engine=xelatex \
      --filter pandoc-citeproc #{File.basename(paper.paper_path)} \
      --template #{latex_template_path}`

      if File.exists?("#{paper.directory}/#{paper.filename_doi}.pdf")
        `open #{paper.directory}/#{paper.filename_doi}.pdf`
      else
        puts "Looks like we failed to compile the PDF"
      end
    end

    def generate_xml
      xml_template_path = "#{Dir.pwd}/resources/xml.template"

      `cd #{paper.directory} && pandoc \
      -V repository=#{repository_address} \
      -V archive_doi=#{archive_doi} \
      -V formatted_doi=#{paper.formatted_doi} \
      -V paper_url=#{paper.pdf_url} \
      -V review_issue_url=#{paper.review_issue_url} \
      -s -f markdown #{File.basename(paper.paper_path)} -o #{paper.filename_doi}.xml \
      --filter pandoc-citeproc \
      --template #{xml_template_path}`

      if File.exists?("#{paper.directory}/#{paper.filename_doi}.xml")
        `open #{paper.directory}/#{paper.filename_doi}.xml`
      else
        puts "Looks like we failed to compile the XML"
      end
    end

    def generate_html(paper_issue=nil, paper_volume=nil, paper_year=nil, paper_month=nil, paper_day=nil)
      html_template_path = "#{Dir.pwd}/resources/html.template"
      google_authors = paper.google_scholar_authors

      paper_year ||= Time.now.strftime('%Y')
      paper_issue ||= CURRENT_ISSUE
      paper_volume ||= CURRENT_VOLUME

      `cd #{paper.directory} && pandoc \
      -V repository=#{repository_address} \
      -V archive_doi=#{archive_doi} \
      -V formatted_doi=#{paper.formatted_doi} \
      -V google_authors='#{google_authors}' \
      -V journal_url='#{JOURNAL_URL}' \
      -V timestamp='#{paper_year}/#{paper_month}/#{paper_day}' \
      -V paper_url=#{paper.pdf_url} \
      -V year=#{paper_year} \
      -V issue=#{paper_issue} \
      -V volume=#{paper_volume} \
      -V review_issue_url=#{paper.review_issue_url} \
      -V citation_author="#{paper.citation_author}" \
      -V paper_title="#{paper.title}" \
      -V page=#{paper.review_issue_id} \
      -s -f markdown #{File.basename(paper.paper_path)} -o #{paper.filename_doi}.html \
      --filter pandoc-citeproc \
      --ascii \
      --template #{html_template_path}`

      if File.exists?("#{paper.directory}/#{paper.filename_doi}.html")
        `open #{paper.directory}/#{paper.filename_doi}.html`
      else
        puts "Looks like we failed to compile the HTML"
      end
    end

    def generate_crossref(paper_issue=nil, paper_volume=nil, paper_year=nil, paper_month=nil, paper_day=nil)
      cross_ref_template_path = "#{Dir.pwd}/resources/crossref.template"
      bibtex = Bibtex.new(find_bib_path.first)
      citations = bibtex.generate_citations
      authors = paper.crossref_authors
      # TODO fix this when we update the DOI URLs
      # crossref_doi = archive_doi.gsub("http://dx.doi.org/", '')

      paper_day ||= Time.now.strftime('%d')
      paper_month ||= Time.now.strftime('%m')
      paper_year ||= Time.now.strftime('%Y')
      paper_issue ||= CURRENT_ISSUE
      paper_volume ||= CURRENT_VOLUME

      `cd #{paper.directory} && pandoc \
      -V timestamp=#{Time.now.strftime('%Y%m%d%H%M%S')} \
      -V doi_batch_id=#{generate_doi_batch_id} \
      -V formatted_doi=#{paper.formatted_doi} \
      -V archive_doi=#{archive_doi} \
      -V review_issue_url=#{paper.review_issue_url} \
      -V paper_url=#{paper.pdf_url} \
      -V joss_resource_url=#{paper.joss_resource_url} \
      -V journal_url=#{JOURNAL_URL} \
      -V citations='#{citations}' \
      -V authors='#{authors}' \
      -V month=#{paper_month} \
      -V day=#{paper_day} \
      -V year=#{paper_year} \
      -V issue=#{paper_issue} \
      -V volume=#{paper_volume} \
      -V page=#{paper.review_issue_id} \
      -s -f markdown #{File.basename(paper.paper_path)} -o #{paper.filename_doi}.crossref.xml \
      --template #{cross_ref_template_path}`

      if File.exists?("#{paper.directory}/#{paper.filename_doi}.crossref.xml")
        `open #{paper.directory}/#{paper.filename_doi}.crossref.xml`
      else
        puts "Looks like we failed to compile the Crossref XML"
      end
    end

    # http://www.crossref.org/help/schema_doc/4.3.7/4.3.7.html
    # Publisher generated ID that uniquely identifies the DOI submission
    # batch. It will be used as a reference in error messages sent by the MDDB, and can be
    # used for submission tracking. The publisher must insure that this number is unique
    # for every submission to CrossRef.
    def generate_doi_batch_id
      @doi_batch_id = SecureRandom.hex
    end
  end
end
