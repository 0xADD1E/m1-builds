class Openjdk < Formula
  # TODO: Update GA archive when JEP391 is merged
  desc "Development kit for the Java programming language"
  homepage "https://openjdk.java.net/"
  url "https://github.com/openjdk/jdk-sandbox/archive/a56ddad05cf1808342aeff1b1cd2b0568a6cdc3a.tar.gz"
  version "16"
  sha256 "29df31b5eefb5a6c016f50b2518ca29e8e61e3cfc676ed403214e1f13a78efd5"
  license :cannot_represent

  bottle do
    cellar :any
  end

  keg_only "it shadows the macOS `java` wrapper"

  depends_on "autoconf" => :build

  # From https://jdk.java.net/
  # http://openjdk.java.net/groups/build/doc/building.html#boot-jdk-requirements
  # TODO: Determine if N-1 is advised in a future release
  #   e.g. "configure: (Your Build JDK must be version 16)"
  resource "boot-jdk" do
    on_macos do
      url "https://download.java.net/java/early_access/jdk16/29/GPL/openjdk-16-ea+29_osx-x64_bin.tar.gz"
      sha256 "f2f99ddc9faf2caf583043828104a67b88af73d010521aa1818d54ac850a932e"
    end
  end

  # Calculate Xcode's dual-arch JavaNativeFoundation.framework path
  def framework_path
    File.expand_path("../SharedFrameworks/ContentDeliveryServices.framework/Versions/Current/itms/java/Frameworks",
      MacOS::Xcode.prefix)
  end

  def install
    boot_jdk_dir = Pathname.pwd/"boot-jdk"
    resource("boot-jdk").stage boot_jdk_dir
    boot_jdk = boot_jdk_dir.to_s

    on_macos do
      boot_jdk += "/Contents/Home"
    end

    java_options = ENV.delete("_JAVA_OPTIONS")

    # Inspecting .hgtags to find a build number
    # The file looks like this:
    #
    # fd07cdb26fc70243ef23d688b545514f4ddf1c2b jdk-16+13
    # 36b29df125dc88f11657ce93b4998aa9ff5f5d41 jdk-16+14
    #
    build = File.read(".hgtags")
                .scan(/ jdk-#{version}\+(.+)$/)
                .map(&:first)
                .map(&:to_i)
                .max
    raise "cannot find build number in .hgtags" if build.nil?

    configure_args = %W[
      --without-version-pre
      --without-version-opt
      --with-version-build=#{build}
      --with-toolchain-path=/usr/bin
      --with-boot-jdk=#{boot_jdk}
      --with-boot-jdk-jvmargs=#{java_options}
      --with-build-jdk=#{boot_jdk}
      --with-debug-level=release
      --with-native-debug-symbols=none
      --with-jvm-variants=server
    ]
    on_macos do
      configure_args += %W[
        --with-sysroot=#{MacOS.sdk_path}
        --with-extra-ldflags=-headerpad_max_install_names
        --enable-dtrace
      ]

      if Hardware::CPU.arm?
        configure_args += %W[
          --disable-warnings-as-errors
          --openjdk-target=aarch64-apple-darwin
          --with-extra-cflags=-arch\ arm64
          --with-extra-ldflags=-arch\ arm64\ -F#{framework_path}
          --with-extra-cxxflags=-arch\ arm64
        ]
      end
    end

    chmod 0755, "configure"
    system "./configure", *configure_args

    ENV["MAKEFLAGS"] = "JOBS=#{ENV.make_jobs}"
    system "make", "images"

    on_macos do
      jdk = Dir["build/*/images/jdk-bundle/*"].first
      libexec.install jdk => "openjdk.jdk"
      bin.install_symlink Dir["#{libexec}/openjdk.jdk/Contents/Home/bin/*"]
      include.install_symlink Dir["#{libexec}/openjdk.jdk/Contents/Home/include/*.h"]
      include.install_symlink Dir["#{libexec}/openjdk.jdk/Contents/Home/include/darwin/*.h"]
    end

    on_linux do
      jdk = Dir["build/*/jdk"].first
      libexec.install jdk => "openjdk.jdk"
      mkdir_p libexec/"support"
      modules = Dir["build/*/support/modules_libs"].first
      libexec.install modules => "support/modules_libs"
      bin.install_symlink Dir["#{libexec}/openjdk.jdk/bin/*"]
      lib.install_symlink Dir["#{libexec}/openjdk.jdk/lib/*"]
      include.install_symlink Dir["#{libexec}/openjdk.jdk/include/*.h"]
      include.install_symlink Dir["#{libexec}/openjdk.jdk/include/linux/*.h"]
    end
  end

  def post_install
    on_macos do
      # Copy JavaNativeFoundation.framework from Xcode after install to avoid signature corruption
      if Hardware::CPU.arm?
        cp_r "#{framework_path}/JavaNativeFoundation.framework",
          "#{libexec}/openjdk.jdk/Contents/Home/lib/JavaNativeFoundation.framework",
          remove_destination: true
      end
    end
  end

  def caveats
    <<~EOS
      For the system Java wrappers to find this JDK, symlink it with
        sudo ln -sfn #{opt_libexec}/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk
    EOS
  end

  test do
    (testpath/"HelloWorld.java").write <<~EOS
      class HelloWorld {
        public static void main(String args[]) {
          System.out.println("Hello, world!");
        }
      }
    EOS

    system bin/"javac", "HelloWorld.java"

    assert_match "Hello, world!", shell_output("#{bin}/java HelloWorld")
  end
end
