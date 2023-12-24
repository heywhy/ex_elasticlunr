import Config

config :git_hooks,
  hooks: [
    commit_msg: [
      tasks: [
        {:cmd, "mix git_ops.check_message", include_hook_args: true}
      ]
    ],
    pre_commit: [
      tasks: [
        cmd: "mix format --check-formatted",
        cmd: "mix credo --strict"
      ]
    ],
    pre_push: [
      tasks: [
        cmd: "mix dialyzer",
        cmd: "mix test --color"
      ]
    ]
  ]

config :git_ops,
  mix_project: Mix.Project.get!(),
  manage_mix_version?: true,
  manage_readme_version: true,
  repository_url: "https://github.com/heywhy/ex_elasticlunr",
  version_tag_prefix: "v"
