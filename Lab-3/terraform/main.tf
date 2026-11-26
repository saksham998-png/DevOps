terraform {
  required_version = ">= 1.5"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Uses DOCKER_HOST if set; on Docker Desktop for Windows pass
#   -var 'docker_host=npipe:////./pipe/docker_engine'
provider "docker" {
  host = var.docker_host
}

resource "docker_network" "lab3" {
  name = "lab3-terraform"
}

resource "docker_image" "taskboard" {
  name = "taskboard:terraform"
  build {
    context = "${path.module}/.."
  }
  # rebuild when the app source changes
  triggers = {
    src = sha1(join("", [for f in fileset("${path.module}/../app", "*.py") : filesha1("${path.module}/../app/${f}")]))
  }
}

resource "docker_container" "taskboard" {
  count    = var.replicas
  name     = "taskboard-tf-${count.index + 1}"
  image    = docker_image.taskboard.image_id
  restart  = "unless-stopped"
  must_run = true

  env = [
    "APP_VERSION=tf-${count.index + 1}",
    "FEATURE_PRIORITY_TASKS=${var.feature_priority_tasks}",
  ]

  ports {
    internal = 8000
    external = var.base_port + count.index
  }

  networks_advanced {
    name = docker_network.lab3.name
  }

  healthcheck {
    test     = ["CMD", "python", "-c", "import urllib.request as u; u.urlopen('http://localhost:8000/health')"]
    interval = "15s"
    timeout  = "3s"
    retries  = 3
  }
}
