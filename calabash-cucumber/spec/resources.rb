require 'singleton'

class Resources

  include Singleton

  def self.shared
    Resources.instance
  end

  def travis_ci?
    @travis_ci ||= ENV['TRAVIS']
  end

  def launch_retries
    travis_ci? ? 8 : 2
  end

  def active_xcode_version
    @active_xcode_version ||= RunLoop::XCTools.new.xcode_version
  end

  def resources_dir
    @resources_dir ||= File.expand_path(File.join(File.dirname(__FILE__), 'resources'))
  end

  def irbrc_path
    @irbrc_path ||= File.expand_path(File.join(File.dirname(__FILE__), '..', 'scripts', '.irbrc'))
  end

  def app_bundle_path(bundle_name)
    case bundle_name
      when :lp_simple_example
        return @lp_cal_app_bundle_path ||= File.join(self.resources_dir, 'LPSimpleExample-cal.app')
      when :smoke
        return @smoke_app_bundle_path ||= File.join(self.resources_dir, 'CalSmoke.app')
      when :calabash_not_linked
        return @calabash_not_linked ||= File.join(self.resources_dir, 'CalNotLinked.app')
      when :server_gem_compatibility
        return @server_gem_compatibility_app_bundle_path ||= File.join(self.resources_dir, 'server-gem-compatibility.app')
      else
        raise "unexpected argument '#{bundle_name}'"
    end
  end

  def ipa_path
    @ipa_path ||= File.expand_path(File.join(resources_dir, 'LPSimpleExample-cal.ipa'))
  end

  def bundle_id
    @bundle_id = 'com.lesspainful.example.LPSimpleExample-cal'
  end

  def device_for_mocking
    endpoint = 'http://localhost:37265/'
    # noinspection RubyStringKeysInHashInspection
    version_data =
    {
          'outcome' => 'SUCCESS',
          'app_id' => 'com.littlejoysoftware.Briar-cal',
          'simulator_device' => 'iPhone',
          'version' => '0.10.0',
          'app_name' => 'Briar-cal',
          'iphone_app_emulated_on_ipad' => false,
          '4inch' => false,
          'git' => {
                'remote_origin' => 'git@github.com:calabash/calabash-ios-server.git',
                'branch' => 'master',
                'revision' => 'e494e30'
          },
          'screen_dimensions' => {
                'scale' => 2,
                'width' => 640,
                'sample' => 1,
                'height' => 1136
          },
          'app_version' => '1.4.0',
          'iOS_version' => '8.0',
          'system' => 'x86_64',
          'simulator' => ''
    }
    Calabash::Cucumber::Device.new(endpoint, version_data)
  end

  def server_version(device_or_simulator)
    case device_or_simulator
      when :device
        {}
      when :simulator
        {
              'app_version' => '1.0',
              'outcome' => 'SUCCESS',
              'app_id' => 'com.xamarin.CalSmoke-cal',
              'simulator_device' => 'iPhone',
              'version' => '0.11.0',
              'app_name' => 'CalSmoke-cal',
              'iphone_app_emulated_on_ipad' => false,
              '4inch' => true,
              'git' => {
                    'remote_origin' => 'git@github.com:calabash/calabash-ios-server.git',
                    'branch' => 'develop',
                    'revision' => '652b20b'
              },
              'screen_dimensions' => {
                    'scale' => 2,
                    'width' => 640,
                    'sample' => 1,
                    'height' => 1136
              },
              'iOS_version' => '7.1',
              'system' => 'x86_64',
              'simulator' => 'CoreSimulator 110.2 - Device: iPhone 5 - Runtime: iOS 7.1 (11D167) - DeviceType: iPhone 5',
              'form_factor' => 'iphone 4in'
        }
      else
        raise "expected '#{device_or_simulator}' to be one of #{[:simulator, :device]}"
    end
  end

  def alt_xcode_install_paths
    @alt_xcode_install_paths ||= lambda {
      min_xcode_version = RunLoop::Version.new('5.1.1')
      Dir.glob('/Xcode/*/*.app/Contents/Developer').map do |path|
        xcode_version = path[/(\d\.\d(\.\d)?)/, 0]
        if RunLoop::Version.new(xcode_version) >= min_xcode_version
          path
        else
          nil
        end
      end
    }.call.compact
  end

  def xcode_select_xcode_hash
    @xcode_select_xcode_hash ||= lambda {
      ENV.delete('DEVELOPER_DIR')
      xcode_tools = RunLoop::XCTools.new
      {:path => xcode_tools.xcode_developer_dir,
       :version => xcode_tools.xcode_version}
    }.call
  end

  def alt_xcode_details_hash(skip_versions=[RunLoop::Version.new('6.0')])
    @alt_xcodes_gte_xc51_hash ||= lambda {
      ENV.delete('DEVELOPER_DIR')
      xcode_select_path = RunLoop::XCTools.new.xcode_developer_dir
      paths =  alt_xcode_install_paths
      paths.map do |path|
        begin
          ENV['DEVELOPER_DIR'] = path
          version = RunLoop::XCTools.new.xcode_version
          if path == xcode_select_path
            nil
          elsif skip_versions.include?(version)
            nil
          elsif version >= RunLoop::Version.new('5.1.1')
            {
                  :version => RunLoop::XCTools.new.xcode_version,
                  :path => path
            }
          else
            nil
          end
        ensure
          ENV.delete('DEVELOPER_DIR')
        end
      end
    }.call.compact
  end

  def supported_xcode_version_paths(skip_versions=[RunLoop::Version.new('6.0')])
    @supported_xcode_version_paths ||= lambda {
      developer_dir = ENV.delete('DEVELOPER_DIR')
      ret = [ RunLoop::XCTools.new.xcode_developer_dir ] +
            alt_xcode_details_hash(skip_versions).map { |elm| elm[:path] }
      ENV['DEVELOPER_DIR'] = developer_dir
      ret
    }.call
  end

  def ideviceinstaller_bin_path
    @ideviceinstaller_bin_path ||= `which ideviceinstaller`.chomp!
  end

  def ideviceinstaller_available?
    path = ideviceinstaller_bin_path
    path and File.exist? ideviceinstaller_bin_path
  end

  def ideviceinstaller
    Luffa::IDeviceInstaller.new(ipa_path, bundle_id)
  end

  def idevice_id_bin_path
    @idevice_id_bin_path ||= `which idevice_id`.chomp!
  end

  def idevice_id_available?
    path = idevice_id_bin_path
    path and File.exist? path
  end

  def physical_devices_for_testing(xcode_tools)
    # Xcode 6 + iOS 8 - devices on the same network, whether development or not,
    # appear when calling $ xcrun instruments -s devices. For the purposes of
    # testing, we will only try to connect to devices that are connected via
    # udid.
    @physical_devices_for_testing ||= lambda {
      devices = xcode_tools.instruments(:devices)
      if idevice_id_available?
        white_list = `#{idevice_id_bin_path} -l`.strip.split("\n")
        devices.select do | device |
          white_list.include?(device.udid) && white_list.count(device.udid) == 1
        end
      else
        devices
      end
    }.call
  end
end
