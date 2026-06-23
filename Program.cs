var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "WebApp testing - 062326");

app.Run();
