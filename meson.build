project(
  'nix-serve',
  'cpp',
  version : 'dev',
  default_options : [
    'cpp_std=c++2a',
    'warning_level=3',
    # force keep trialing comma
  ],
)

nix_cmd_dep = dependency('nix-cmd')
httplib_dep = dependency('httplib')
thread_dep = dependency('threads')

executable(
  'nix-serve',
  'nix-serve.cc',
  dependencies : [ nix_cmd_dep, httplib_dep, thread_dep ],
  install : true,
)
