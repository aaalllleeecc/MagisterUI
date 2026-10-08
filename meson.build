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

sources = files(
  'src/main.vala',
  'src/helpers.vala',
  'src/client.vala',
  'src/page.vala',
  'src/appointments-page.vala',
  'src/messages-page.vala',
  'src/grades-page.vala',
  'src/study-guides-page.vala',
  'src/theme.vala',
  'src/window.vala',
  'src/assignments-page.vala',
)

executable('magister-gtk', sources, resources,
  dependencies: deps,
  c_args: ['-w'],
  install: true)