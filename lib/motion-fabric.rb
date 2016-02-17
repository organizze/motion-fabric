# encoding: utf-8

unless defined?(Motion::Project::Config)
  raise "This file must be required within a RubyMotion project Rakefile."
end

class FabricKitConfig
  attr_accessor :name, :info

  def initialize(name)
    @name = name
    @info = {}
  end

  def to_hash
    {
      'KitInfo' => info,
      'KitName' => name
    }
  end
end

class FabricConfig
  attr_accessor :api_key, :build_secret, :kits, :beta_block

  def api_key=(api_key)
    @config.info_plist['Fabric']['APIKey'] = api_key
    @api_key = api_key
  end

  def initialize(config)
    @config = config
    config.info_plist['Fabric'] ||= {}
    config.info_plist['Fabric']['Kits'] ||= []
  end

  def kit(name, &block)
    kit_config = FabricKitConfig.new(name)
    block.call(kit_config.info) if block
    config.info_plist['Fabric']['Kits'] << kit_config.to_hash
  end

  def beta(&block)
    @beta_block = block if block
  end
end

module Motion::Project
  class Config
    variable :fabric

    def fabric(&block)
      @fabric ||= FabricConfig.new(self)
      block.call(@fabric) if block
      @fabric
    end
  end
end

Motion::Project::App.setup do |app|
  app.pods do
    pod 'Fabric'
    pod 'Crashlytics'
  end
end

def fabric_setup(&block)
  pods_root = Motion::Project::CocoaPods::PODS_ROOT
  api_key = App.config.fabric.api_key
  build_secret = App.config.fabric.build_secret

  App.fail "Fabric's api_key cannot be empty" unless api_key
  App.fail "Fabric's build_secret cannot be empty" unless build_secret

  block.call(pods_root, api_key, build_secret)
end

def fabric_run(platform)
  dsym_path = App.config.app_bundle_dsym(platform)
  project_dir = File.expand_path(App.config.project_dir)
  env = {
    BUILT_PRODUCTS_DIR: File.expand_path(File.join(App.config.versionized_build_dir(platform), App.config.bundle_filename)),
    INFOPLIST_PATH: 'Info.plist',
    DWARF_DSYM_FILE_NAME: File.basename(dsym_path),
    DWARF_DSYM_FOLDER_PATH: File.expand_path(File.dirname(dsym_path)),
    PROJECT_DIR: project_dir,
    SRCROOT: project_dir,
    PLATFORM_NAME: platform.downcase,
    PROJECT_FILE_PATH: "",
    CONFIGURATION: App.config_mode ==  'development' ? 'debug' : 'release',
  }
  env_string = env.map { |k,v| "#{k}='#{v}'" }.join(' ')
  fabric_setup do |pods_root, api_key, build_secret|
    App.info "Fabric", "Uploading .dSYM file"
    system("env #{env_string} sh #{pods_root}/Fabric/run #{api_key} #{build_secret}")
  end
end

namespace :fabric do
  task :setup do
    fabric_run(App.config_without_setup.deploy_platform)
    Rake::Task["fabric:dsym:simulator"].invoke
  end

  task :upload do
    App.config.fabric.beta_block.call if App.config.fabric.beta_block

    file = File.join(Dir.tmpdir, 'motion-fabric.rb')
    open(file, 'w') { |io| io.write 'CRASHLYTICS_BETA = true' }
    App.config.files << file
    Rake::Task["archive"].invoke

    fabric_setup do |pods_root, api_key, build_secret|
      App.info "Fabric", "Uploading IPA"
      notes_path = File.join(Dir.tmpdir, 'fabric-notes.txt')
      open(notes_path, 'w') { |io| io.write ENV['notes'] }
      system(%Q{#{pods_root}/Crashlytics/submit #{api_key} #{build_secret} -ipaPath "#{App.config.archive}" -notesPath "#{notes_path}"})
    end
  end

  namespace :dsym do
    task :device do
      fabric_run(App.config_without_setup.deploy_platform)
    end

    task :simulator do
      fabric_run(App.config_without_setup.local_platform)
    end
  end
end