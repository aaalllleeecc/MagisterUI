project('magister-gtk', ['vala', 'c'], version: '0.1.0')

gnome = import('gnome')

deps = [
  dependency('gtk4'),
  dependency('libsoup-3.0'),
  dependency('json-glib-1.0'),
]

resources = gnome.compile_resources(
  'magister-resources',
  'Resources/magister.gresource.xml',
  source_dir: 'Resources',
)

executable('magister-gtk', 'src/main.vala', resources,
  dependencies: deps,
  c_args: ['-w'],
  install: true)