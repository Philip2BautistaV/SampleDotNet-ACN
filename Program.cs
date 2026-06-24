var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "DBG pipeline test - 062426");

app.Run();
