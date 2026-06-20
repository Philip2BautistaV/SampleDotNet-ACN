var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "BestDay of my Life!!!");

app.Run();
