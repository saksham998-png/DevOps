output "urls" {
  description = "One URL per replica"
  value       = [for c in docker_container.taskboard : "http://localhost:${c.ports[0].external}"]
}

output "container_names" {
  value = docker_container.taskboard[*].name
}
