platform :ios, '7.0'

# Inform CocoaPods that we use some custom build configurations
xcodeproj 'CrushBootstrap', 'AdHoc' => :release, 'Profile' => :release, 'Test' => :debug

# The Crush Bootstrap lib
pod 'CRLLib', :git => 'https://github.com/crushlovely/CRLLib.git'

# Logging & Analytics
pod 'CocoaLumberjack'
pod 'CrashlyticsFramework'
pod 'CrashlyticsLumberjack'

# Networking
pod 'AFNetworking'

# Various goodies
pod 'libextobjc'      # Useful macros and some craziness
pod 'PixateFreestyle' # Style your app with CSS
pod 'FormatterKit'    # For all your string formatting needs

# You may want...
#pod 'OMPromises'     # Promises/A+-alike
#pod 'ReactiveCocoa'  # It's a lifestyle
#pod 'Mantle'         # Github's model framework
#pod 'SSKeychain'     # Go-to keychain wrapper
#pod 'Asterism'       # Nice & fast collection operations
#pod 'DateTools'      # Datetime heavy lifting

# Testing necessities
target 'Specs', :exclusive => true do
  pod 'Specta'
  pod 'Expecta'
  pod 'OCMockito'

# pod 'OHHTTPStubs'
end
