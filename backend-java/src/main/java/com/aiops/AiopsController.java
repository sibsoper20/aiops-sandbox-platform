package com.aiops;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.HashMap;
import java.util.Map;

@Controller
public class AiopsController {

    private final WebClient webClient;

    public AiopsController() {
        this.webClient = WebClient.builder()
                .baseUrl("http://localhost:5050")
                .build();
    }

    @GetMapping("/")
    public String index() {
        return "index";
    }

    @PostMapping("/ask")
    public String ask(@RequestParam String question,
                      @RequestParam String dataType,
                      Model model) {

        String url = dataType.equals("metrics") ? "/analyze-metrics" : "/analyze-logs";

        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("question", question);
        if (dataType.equals("metrics")) {
            requestBody.put("metrics", "[{\"timestamp\": \"2024-04-01\", \"cpu\": 70}, {\"timestamp\": \"2024-04-02\", \"cpu\": 85}]");
        } else {
            requestBody.put("logs", "2024-04-01 ERROR OutOfMemory\n2024-04-01 INFO Restarting service");
        }

        String response;
        try {
            String rawResponse = webClient.post()
                    .uri(url)
                    .header("Content-Type", "application/json")
                    .bodyValue(requestBody)
                    .retrieve()
                    .bodyToMono(String.class)
                    .block();

            ObjectMapper mapper = new ObjectMapper();
            JsonNode root = mapper.readTree(rawResponse);
            response = root.path("analysis").asText();
        } catch (WebClientResponseException e) {
            System.err.println("HTTP error from Flask: " + e.getStatusCode() + " - " + e.getResponseBodyAsString());
            response = "HTTP error: " + e.getStatusCode();
        } catch (Exception e) {
            e.printStackTrace();
            response = "Error calling Python service: " + e.getMessage();
        }

        model.addAttribute("response", response);
        return "index";
    }
}
