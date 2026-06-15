var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "Final test for Today - 06/15/2026");

app.Run();
