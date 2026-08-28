function bazel-resync

echo "resolved=[]" > resolved.bzl
bazel sync;
end
