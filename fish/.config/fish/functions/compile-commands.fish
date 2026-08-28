function compile-commands
bazel run @hedron_compile_commands//:refresh_all -- --config=x86_64
end
