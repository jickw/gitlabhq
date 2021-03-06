require "spec_helper"

describe WikiPage do
  let(:project) { create(:project) }
  let(:user) { project.owner }
  let(:wiki) { ProjectWiki.new(project, user) }

  subject { described_class.new(wiki) }

  describe '.group_by_directory' do
    context 'when there are no pages' do
      it 'returns an empty array' do
        expect(described_class.group_by_directory(nil)).to eq([])
        expect(described_class.group_by_directory([])).to eq([])
      end
    end

    context 'when there are pages' do
      before do
        create_page('dir_1/dir_1_1/page_3', 'content')
        create_page('dir_1/page_2', 'content')
        create_page('dir_2/page_5', 'content')
        create_page('dir_2/page_4', 'content')
        create_page('page_1', 'content')
      end
      let(:page_1) { wiki.find_page('page_1') }
      let(:dir_1) do
        WikiDirectory.new('dir_1', [wiki.find_page('dir_1/page_2')])
      end
      let(:dir_1_1) do
        WikiDirectory.new('dir_1/dir_1_1', [wiki.find_page('dir_1/dir_1_1/page_3')])
      end
      let(:dir_2) do
        pages = [wiki.find_page('dir_2/page_5'),
                 wiki.find_page('dir_2/page_4')]
        WikiDirectory.new('dir_2', pages)
      end

      it 'returns an array with pages and directories' do
        expected_grouped_entries = [page_1, dir_1, dir_1_1, dir_2]

        grouped_entries = described_class.group_by_directory(wiki.pages)

        grouped_entries.each_with_index do |page_or_dir, i|
          expected_page_or_dir = expected_grouped_entries[i]
          expected_slugs = get_slugs(expected_page_or_dir)
          slugs = get_slugs(page_or_dir)

          expect(slugs).to match_array(expected_slugs)
        end
      end

      it 'returns an array sorted by alphabetical position' do
        # Directories and pages within directories are sorted alphabetically.
        # Pages at root come before everything.
        expected_order = ['page_1', 'dir_1/page_2', 'dir_1/dir_1_1/page_3',
                          'dir_2/page_4', 'dir_2/page_5']

        grouped_entries = described_class.group_by_directory(wiki.pages)

        actual_order =
          grouped_entries.map do |page_or_dir|
            get_slugs(page_or_dir)
          end
          .flatten
        expect(actual_order).to eq(expected_order)
      end
    end
  end

  describe '.unhyphenize' do
    it 'removes hyphens from a name' do
      name = 'a-name--with-hyphens'

      expect(described_class.unhyphenize(name)).to eq('a name with hyphens')
    end
  end

  describe "#initialize" do
    context "when initialized with an existing gollum page" do
      before do
        create_page("test page", "test content")
        @page = wiki.wiki.paged("test page")
        @wiki_page = described_class.new(wiki, @page, true)
      end

      it "sets the slug attribute" do
        expect(@wiki_page.slug).to eq("test-page")
      end

      it "sets the title attribute" do
        expect(@wiki_page.title).to eq("test page")
      end

      it "sets the formatted content attribute" do
        expect(@wiki_page.content).to eq("test content")
      end

      it "sets the format attribute" do
        expect(@wiki_page.format).to eq(:markdown)
      end

      it "sets the message attribute" do
        expect(@wiki_page.message).to eq("test commit")
      end

      it "sets the version attribute" do
        expect(@wiki_page.version).to be_a Gollum::Git::Commit
      end
    end
  end

  describe "validations" do
    before do
      subject.attributes = { title: 'title', content: 'content' }
    end

    it "validates presence of title" do
      subject.attributes.delete(:title)
      expect(subject.valid?).to be_falsey
    end

    it "validates presence of content" do
      subject.attributes.delete(:content)
      expect(subject.valid?).to be_falsey
    end
  end

  before do
    @wiki_attr = { title: "Index", content: "Home Page", format: "markdown" }
  end

  describe "#create" do
    after do
      destroy_page("Index")
    end

    context "with valid attributes" do
      it "saves the wiki page" do
        subject.create(@wiki_attr)
        expect(wiki.find_page("Index")).not_to be_nil
      end

      it "returns true" do
        expect(subject.create(@wiki_attr)).to eq(true)
      end
    end
  end

  describe "dot in the title" do
    let(:title) { 'Index v1.2.3' }

    before do
      @wiki_attr = { title: title, content: "Home Page", format: "markdown" }
    end

    describe "#create" do
      after do
        destroy_page(title)
      end

      context "with valid attributes" do
        it "saves the wiki page" do
          subject.create(@wiki_attr)
          expect(wiki.find_page(title)).not_to be_nil
        end

        it "returns true" do
          expect(subject.create(@wiki_attr)).to eq(true)
        end
      end
    end

    describe "#update" do
      before do
        create_page(title, "content")
        @page = wiki.find_page(title)
      end

      it "updates the content of the page" do
        @page.update("new content")
        @page = wiki.find_page(title)
      end

      it "returns true" do
        expect(@page.update("more content")).to be_truthy
      end
    end
  end

  describe "#update" do
    before do
      create_page("Update", "content")
      @page = wiki.find_page("Update")
    end

    after do
      destroy_page("Update")
    end

    context "with valid attributes" do
      it "updates the content of the page" do
        @page.update("new content")
        @page = wiki.find_page("Update")
      end

      it "returns true" do
        expect(@page.update("more content")).to be_truthy
      end
    end

    context 'with same last commit sha' do
      it 'returns true' do
        expect(@page.update('more content', last_commit_sha: @page.last_commit_sha)).to be_truthy
      end
    end

    context 'with different last commit sha' do
      it 'raises exception' do
        expect { @page.update('more content', last_commit_sha: 'xxx') }.to raise_error(WikiPage::PageChangedError)
      end
    end
  end

  describe "#destroy" do
    before do
      create_page("Delete Page", "content")
      @page = wiki.find_page("Delete Page")
    end

    it "deletes the page" do
      @page.delete
      expect(wiki.pages).to be_empty
    end

    it "returns true" do
      expect(@page.delete).to eq(true)
    end
  end

  describe "#versions" do
    before do
      create_page("Update", "content")
      @page = wiki.find_page("Update")
    end

    after do
      destroy_page("Update")
    end

    it "returns an array of all commits for the page" do
      3.times { |i| @page.update("content #{i}") }
      expect(@page.versions.count).to eq(4)
    end
  end

  describe "#title" do
    before do
      create_page("Title", "content")
      @page = wiki.find_page("Title")
    end

    after do
      destroy_page("Title")
    end

    it "replaces a hyphen to a space" do
      @page.title = "Import-existing-repositories-into-GitLab"
      expect(@page.title).to eq("Import existing repositories into GitLab")
    end
  end

  describe '#directory' do
    context 'when the page is at the root directory' do
      it 'returns an empty string' do
        create_page('file', 'content')
        page = wiki.find_page('file')

        expect(page.directory).to eq('')
      end
    end

    context 'when the page is inside an actual directory' do
      it 'returns the full directory hierarchy' do
        create_page('dir_1/dir_1_1/file', 'content')
        page = wiki.find_page('dir_1/dir_1_1/file')

        expect(page.directory).to eq('dir_1/dir_1_1')
      end
    end
  end

  describe '#historical?' do
    before do
      create_page('Update', 'content')
      @page = wiki.find_page('Update')
      3.times { |i| @page.update("content #{i}") }
    end

    after do
      destroy_page('Update')
    end

    it 'returns true when requesting an old version' do
      old_version = @page.versions.last.to_s
      old_page = wiki.find_page('Update', old_version)

      expect(old_page.historical?).to eq true
    end

    it 'returns false when requesting latest version' do
      latest_version = @page.versions.first.to_s
      latest_page = wiki.find_page('Update', latest_version)

      expect(latest_page.historical?).to eq false
    end

    it 'returns false when version is nil' do
      latest_page = wiki.find_page('Update', nil)

      expect(latest_page.historical?).to eq false
    end
  end

  describe '#to_partial_path' do
    it 'returns the relative path to the partial to be used' do
      page = build(:wiki_page)

      expect(page.to_partial_path).to eq('projects/wikis/wiki_page')
    end
  end

  describe '#==' do
    let(:original_wiki_page) { create(:wiki_page) }

    it 'returns true for identical wiki page' do
      expect(original_wiki_page).to eq(original_wiki_page)
    end

    it 'returns false for updated wiki page' do
      updated_wiki_page = original_wiki_page.update("Updated content")
      expect(original_wiki_page).not_to eq(updated_wiki_page)
    end
  end

  describe '#last_commit_sha' do
    before do
      create_page("Update", "content")
      @page = wiki.find_page("Update")
    end

    after do
      destroy_page("Update")
    end

    it 'returns commit sha' do
      expect(@page.last_commit_sha).to eq @page.commit.sha
    end

    it 'is changed after page updated' do
      last_commit_sha_before_update = @page.last_commit_sha

      @page.update("new content")
      @page = wiki.find_page("Update")

      expect(@page.last_commit_sha).not_to eq last_commit_sha_before_update
    end
  end

  private

  def remove_temp_repo(path)
    FileUtils.rm_rf path
  end

  def commit_details
    { name: user.name, email: user.email, message: "test commit" }
  end

  def create_page(name, content)
    wiki.wiki.write_page(name, :markdown, content, commit_details)
  end

  def destroy_page(title)
    page = wiki.wiki.paged(title)
    wiki.wiki.delete_page(page, commit_details)
  end

  def get_slugs(page_or_dir)
    if page_or_dir.is_a? WikiPage
      [page_or_dir.slug]
    else
      page_or_dir.pages.present? ? page_or_dir.pages.map(&:slug) : []
    end
  end
end
