package com.aiops;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

@Controller
public class AiopsController {

    private final WebClient webClient;

    public AiopsController() {
        this.webClient = WebClient.builder().baseUrl("http://localhost:5000").build();
    }

    @GetMapping("/")
    public String index() {
        return "index";
    }

    @PostMapping("/ask")
    public String ask(@RequestParam String question, @RequestParam String dataType, Model model) {
        String url = dataType.equals("metrics") ? "/analyze-metrics" : "/analyze-logs";
        String dummyData = dataType.equals("metrics")
                ? "[{\"timestamp\": \"2024-04-01\", \"cpu\": 70}, {\"timestamp\": \"2024-04-02\", \"cpu\": 85}]"
                : "2024-04-01 ERROR OutOfMemory\n2024-04-01 INFO Restarting service";

        String payload = String.format("{\"%s\": \"%s\", \"question\": \"%s\"}",
                dataType.equals("metrics") ? "metrics" : "logs", dummyData, question);

        String response = webClient.post()
                .uri(url)
                .header("Content-Type", "application/json")
                .bodyValue(payload)
                .retrieve()
                .bodyToMono(String.class)
                .onErrorReturn("Error calling Python service")
                .block();

        model.addAttribute("response", response);
        return "index";
    }
}
