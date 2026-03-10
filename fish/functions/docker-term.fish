function docker-term
    docker compose -f compose.dev.yaml exec workspace bash
end
