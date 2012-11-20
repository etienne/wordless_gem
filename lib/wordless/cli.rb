require 'thor'
require 'yaml'
require 'net/http'
require 'rbconfig'
require 'tempfile'
require 'wordpress_tools/cli'
require 'wordless/cli_helper'
require 'active_support/all'

module Wordless
  class CLI < Thor
    include Thor::Actions
    include Wordless::CLIHelper

    @@lib_dir = File.expand_path(File.dirname(__FILE__))
    @@config = if File.exists?('Wordfile')
                 YAML::load(File.open('Wordfile')).symbolize_keys
               else
                 {}
               end

    no_tasks do
      def wordless_repo
        @@config[:wordless_repo] || 'git://github.com/welaika/wordless.git'
      end
    end

    desc "new [NAME]", "download WordPress in specified directory, install the Wordless plugin and create a Wordless theme"
    method_option :locale, :aliases => "-l", :desc => "WordPress locale (default is en_US)"
    def new(name)
      WordPressTools::CLI.new.invoke('new', [name], :bare => true, :locale => options['locale'])
      Dir.chdir(name)
      install
      theme(name)
    end

    desc "install", "install the Wordless plugin into an existing WordPress installation"
    def install
      unless git_installed?
        error "Git is not available. Please install git."
        return
      end

      unless File.directory? 'wp-content/plugins'
        error "Directory 'wp-content/plugins' not found. Make sure you're at the root level of a WordPress installation."
        return
      end

      if add_git_repo wordless_repo, 'wp-content/plugins/wordless'
        success "Installed Wordless plugin."
      else
        error "There was an error installing the Wordless plugin."
      end
    end

    desc "theme NAME", "create a new Wordless theme NAME"
    def theme(name)
      unless File.directory? 'wp-content/themes'
        error "Directory 'wp-content/themes' not found. Make sure you're at the root level of a WordPress installation."
        return
      end

      # Run PHP helper script
      if system "php #{File.join(@@lib_dir, 'theme_builder.php')} #{name}"
        success "Created a new Wordless theme in 'wp-content/themes/#{name}'."
      else
        error "Couldn't create Wordless theme."
        return
      end
    end

    desc "compile", "compile static assets"
    def compile
      if system "php #{File.join(@@lib_dir, 'compile_assets.php')}"
        success "Compiled static assets."
      else
        error "Couldn't compile static assets."
      end
    end

    desc "clean", "clean static assets"
    def clean
      unless File.directory? 'wp-content/themes'
        error "Directory 'wp-content/themes' not found. Make sure you're at the root level of a WordPress installation."
        return
      end

      static_css = Array(@@config[:static_css] || Dir['wp-content/themes/*/assets/stylesheets/screen.css'])
      static_js = Array(@@config[:static_js] || Dir['wp-content/themes/*/assets/javascripts/application.js'])

      begin
        (static_css + static_js).each do |file|
          FileUtils.rm_f(file) if File.exists?(file)
        end
        success "Cleaned static assets."
      rescue
        error "Couldn't clean static assets."
      end
    end

    desc "deploy", "deploy your wordpress using the deploy_command defined in your Wordfile"
    method_option :refresh, :aliases => "-r", :desc => "compile static assets before deploying and clean them after"
    method_option :command, :aliases => "-c", :desc => "use a custom deploy command"
    def deploy
      unless File.exists? 'wp-config.php'
        error "Wordpress not found. Make sure you're at the root level of a WordPress installation."
        return
      end

      compile if options['refresh']

      deploy_command = options['command'].presence || @@config[:deploy_command]

      if deploy_command
        system "#{deploy_command}"
      else
        error "deploy_command not set. Make sure it is included in your Wordfile"
      end

      clean if options['refresh']
    end
  end
end
